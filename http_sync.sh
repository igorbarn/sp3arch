#!/bin/bash

# Конфигурация
CONFIG_FILE="/etc/http_sync.conf"

# Загрузка конфигурации
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    # Значения по умолчанию
    SOURCE_URL="http://example.com/files/"
    DEST_DIR="/var/http_files"
    LOG_FILE="/var/log/http_sync.log"
    MAX_AGE_DAYS=30
    BACKUP_OLD_FILES=true
    BACKUP_DIR="/var/http_files_backup"
    TEMP_DIR="/tmp/http_sync"
fi

# Создание необходимых директорий
mkdir -p "$DEST_DIR"
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$TEMP_DIR"

# Логирование
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Получение списка файлов из HTTP источника
get_http_file_list() {
    local url="$1"
    local temp_file="$TEMP_DIR/http_list.txt"
    
    log "Получение списка файлов из источника: $url"
    
    if command -v wget > /dev/null; then
        wget -q -O - "$url" > "$temp_file"
    elif command -v curl > /dev/null; then
        curl -s "$url" > "$temp_file"
    else
        log "ОШИБКА: Не найден wget или curl"
        return 1
    fi
    
    # Парсим HTML чтобы извлечь ссылки на файлы
    # Этот метод может потребовать адаптации под конкретный сервер
    grep -o 'href="[^"]*"' "$temp_file" | \
        sed 's/href="//g' | sed 's/"$//g' | \
        grep -v -E '(\.\.|/$)' > "$TEMP_DIR/file_list.txt"
    
    local file_count=$(wc -l < "$TEMP_DIR/file_list.txt")
    log "Найдено файлов в источнике: $file_count"
    
    # Логируем содержимое каталога (первые 20 файлов)
    if [ $file_count -gt 0 ]; then
        log "Содержимое каталога HTTP источника (первые 20 файлов):"
        head -20 "$TEMP_DIR/file_list.txt" | while read file; do
            log "  - $file"
        done
        if [ $file_count -gt 20 ]; then
            log "  ... и еще $((file_count - 20)) файлов"
        fi
    fi
    
    echo "$file_count"
}

# Резервное копирование старых файлов
backup_old_files() {
    if [ "$BACKUP_OLD_FILES" = true ]; then
        mkdir -p "$BACKUP_DIR"
        local backup_name="backup_$(date '+%Y%m%d_%H%M%S')"
        
        # Копируем только если в директории есть файлы
        if [ "$(ls -A "$DEST_DIR" 2>/dev/null)" ]; then
            cp -r "$DEST_DIR" "$BACKUP_DIR/$backup_name" 2>/dev/null
            log "Создана резервная копия: $backup_name"
        else
            log "Резервное копирование пропущено (целевая директория пуста)"
        fi
    fi
}

# Основная синхронизация
sync_files() {
    log "Запуск синхронизации из $SOURCE_URL"
    
    # Проверка доступности источника
    if ! curl -s --head "$SOURCE_URL" > /dev/null; then
        log "ОШИБКА: Источник недоступен"
        return 1
    fi
    
    # Получаем список файлов и их количество
    local source_file_count=$(get_http_file_list "$SOURCE_URL")
    if [ -z "$source_file_count" ] || [ "$source_file_count" -eq 0 ]; then
        log "ПРЕДУПРЕЖДЕНИЕ: В источнике не найдено файлов"
    fi
    
    # Создание резервной копии
    backup_old_files
    
    # Подсчет файлов до скачивания
    local files_before=0
    if [ -d "$DEST_DIR" ]; then
        files_before=$(find "$DEST_DIR" -type f | wc -l)
    fi
    
    log "Файлов в локальном каталоге до синхронизации: $files_before"
    
    # Скачивание файлов с wget
    local downloaded_count=0
    if command -v wget > /dev/null; then
        log "Начало скачивания файлов с wget"
        wget -r -np -nH -nd -P "$DEST_DIR" \
             --progress=dot:giga \
             "$SOURCE_URL" >> "$LOG_FILE" 2>&1
        
        if [ $? -eq 0 ]; then
            # Подсчет скачанных файлов
            local files_after=$(find "$DEST_DIR" -type f | wc -l)
            downloaded_count=$((files_after - files_before))
            log "Успешно скачано файлов: $downloaded_count"
        else
            log "ОШИБКА: wget завершился с ошибкой"
            return 1
        fi
    else
        log "ОШИБКА: wget не установлен"
        return 1
    fi
    
    # Логируем итоговое состояние
    local total_files=$(find "$DEST_DIR" -type f | wc -l)
    log "ИТОГО: Файлов в локальном каталоге: $total_files"
    
    return 0
}

# Очистка временных файлов
cleanup_temp() {
    rm -rf "$TEMP_DIR"/* 2>/dev/null
    log "Временные файлы очищены"
}

# Очистка старых логов и резервных копий
cleanup() {
    # Очистка логов
    find "$(dirname "$LOG_FILE")" -name "$(basename "$LOG_FILE")*" \
         -type f -mtime +$MAX_AGE_DAYS -delete 2>/dev/null
    
    # Очистка старых резервных копий (старше 7 дней)
    if [ -d "$BACKUP_DIR" ]; then
        local backup_count=$(find "$BACKUP_DIR" -type d -name "backup_*" | wc -l)
        if [ $backup_count -gt 5 ]; then  # Оставляем только 5 последних бэкапов
            find "$BACKUP_DIR" -type d -name "backup_*" -exec ls -dt {} + | \
            tail -n +6 | xargs rm -rf 2>/dev/null
            log "Удалены старые резервные копии (оставлено 5 последних)"
        fi
    fi
    
    cleanup_temp
}

# Основной код
main() {
    log "=== Начало выполнения скрипта ==="
    log "Источник: $SOURCE_URL"
    log "Целевая директория: $DEST_DIR"
    
    if sync_files; then
        log "Синхронизация завершена успешно"
    else
        log "Синхронизация завершена с ошибками"
        exit 1
    fi
    
    cleanup
    log "=== Завершение выполнения скрипта ==="
}

# Запуск основной функции
main "$@"