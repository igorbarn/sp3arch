#!/bin/bash

# 04/11/25
# Улучшенный скрипт с поддержкой локального и удаленного источников
# Базовые настройки
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$HOME/.config/http_sync/http_sync.conf"
DEFAULT_CONFIG_FILE="$SCRIPT_DIR/http_sync.conf"

# Поиск конфигурационного файла
find_config() {
    # 1. Проверяем ~/.config/http_sync/
    if [ -f "$CONFIG_FILE" ]; then
        echo "$CONFIG_FILE"
        return 0
    fi
    
    # 2. Проверяем рядом со скриптом
    if [ -f "$DEFAULT_CONFIG_FILE" ]; then
        echo "$DEFAULT_CONFIG_FILE"
        return 0
    fi
    
    # 3. Проверяем в текущей директории
    if [ -f "./http_sync.conf" ]; then
        echo "./http_sync.conf"
        return 0
    fi
    
    return 1
}

# Загрузка конфигурации
load_config() {
    local config_file=$(find_config)
    
    if [ -n "$config_file" ]; then
        log "Используется конфигурационный файл: $config_file"
        source "$config_file"
    else
        log "ПРЕДУПРЕЖДЕНИЕ: Конфигурационный файл не найден, используются значения по умолчанию"
        set_default_config
    fi
    
    # Валидация конфигурации
    validate_config
}

# Валидация конфигурации
validate_config() {
    if [[ "$SOURCE_TYPE" != "local" && "$SOURCE_TYPE" != "remote" ]]; then
        log "ОШИБКА: Неверный тип источника. Допустимые значения: local или remote"
        exit 1
    fi
    
    if [ -z "$SOURCE_PATH" ]; then
        log "ОШИБКА: SOURCE_PATH не задан"
        exit 1
    fi
    
    if [ -z "$DEST_DIR" ]; then
        log "ОШИБКА: DEST_DIR не задан"
        exit 1
    fi
}

# Значения по умолчанию
set_default_config() {
    SOURCE_TYPE="local"                  # local или remote
    SOURCE_PATH="/tmp/source_files"      # Локальный путь или URL
    DEST_DIR="$HOME/http_files"
    LOG_FILE="$HOME/.local/share/http_sync/http_sync.log"
    MAX_AGE_DAYS=30
    BACKUP_OLD_FILES=true
    BACKUP_DIR="$HOME/http_files_backup"
    TEMP_DIR="/tmp/http_sync_$USER"
}

# Создание необходимых директорий
create_directories() {
    mkdir -p "$DEST_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "$TEMP_DIR"
    mkdir -p "$(dirname "$CONFIG_FILE")"
    
    # Создаем пример конфигурации если нет файла
    if [ ! -f "$CONFIG_FILE" ] && [ ! -f "$DEFAULT_CONFIG_FILE" ]; then
        create_example_config
    fi
}

# Создание примера конфигурации
create_example_config() {
    local example_config="$HOME/.config/http_sync/http_sync.conf.example"
    cat > "$example_config" << 'EOF'
# Конфигурация синхронизации файлов

# Тип источника: local (локальный) или remote (удаленный HTTP)
SOURCE_TYPE="local"

# Путь к источнику:
# - для SOURCE_TYPE="local": абсолютный путь к директории
# - для SOURCE_TYPE="remote": URL адрес
SOURCE_PATH="/tmp/source_files"

# Локальный каталог для сохранения
DEST_DIR="$HOME/sync_files"

# Файл для логирования
LOG_FILE="$HOME/.local/share/http_sync/sync.log"

# Максимальный возраст логов в днях
MAX_AGE_DAYS=30

# Создавать резервные копии старых файлов
BACKUP_OLD_FILES=true

# Директория для резервных копий
BACKUP_DIR="$HOME/sync_files_backup"

# Временная директория
TEMP_DIR="/tmp/file_sync_$USER"
EOF
    log "Создан пример конфигурационного файла: $example_config"
}

# Логирование
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Получение списка файлов из источника
get_file_list() {
    local source_type="$1"
    local source_path="$2"
    local temp_file="$TEMP_DIR/file_list.txt"
    
    log "Получение списка файлов из источника ($source_type): $source_path"
    
    if [ "$source_type" = "local" ]; then
        get_local_file_list "$source_path"
    elif [ "$source_type" = "remote" ]; then
        get_remote_file_list "$source_path"
    else
        log "ОШИБКА: Неизвестный тип источника: $source_type"
        return 1
    fi
}

# Получение списка файлов из локального источника
get_local_file_list() {
    local source_path="$1"
    
    if [ ! -d "$source_path" ]; then
        log "ОШИБКА: Локальная директория не существует: $source_path"
        return 1
    fi
    
    # Получаем список файлов (только файлы, без директорий)
    find "$source_path" -type f -printf "%P\n" > "$TEMP_DIR/file_list.txt"
    
    local file_count=$(wc -l < "$TEMP_DIR/file_list.txt")
    log "Найдено файлов в локальном источнике: $file_count"
    
    # Логируем содержимое каталога (первые 20 файлов)
    if [ $file_count -gt 0 ]; then
        log "Содержимое локального каталога (первые 20 файлов):"
        head -20 "$TEMP_DIR/file_list.txt" | while read file; do
            if [ -n "$file" ]; then
                local file_size=$(stat -c%s "$source_path/$file" 2>/dev/null || echo "unknown")
                log "  - $file ($file_size bytes)"
            fi
        done
        if [ $file_count -gt 20 ]; then
            log "  ... и еще $((file_count - 20)) файлов"
        fi
    else
        log "ПРЕДУПРЕЖДЕНИЕ: Локальная директория пуста"
    fi
    
    echo "$file_count"
}

# Получение списка файлов из удаленного источника
get_remote_file_list() {
    local source_path="$1"
    local temp_file="$TEMP_DIR/http_list.txt"
    
    # Проверяем доступность источника
    if ! curl -s --head "$source_path" > /dev/null; then
        log "ОШИБКА: Удаленный источник недоступен: $source_path"
        return 1
    fi
    
    if command -v wget > /dev/null; then
        wget -q -O - "$source_path" > "$temp_file"
    elif command -v curl > /dev/null; then
        curl -s "$source_path" > "$temp_file"
    else
        log "ОШИБКА: Не найден wget или curl"
        return 1
    fi
    
    # Парсим HTML чтобы извлечь ссылки на файлы
    grep -o 'href="[^"]*"' "$temp_file" | \
        sed 's/href="//g' | sed 's/"$//g' | \
        grep -v -E '(\.\.|/$)' > "$TEMP_DIR/file_list.txt"
    
    local file_count=$(wc -l < "$TEMP_DIR/file_list.txt")
    log "Найдено файлов в удаленном источнике: $file_count"
    
    # Логируем содержимое каталога (первые 20 файлов)
    if [ $file_count -gt 0 ]; then
        log "Содержимое удаленного каталога (первые 20 файлов):"
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

# Синхронизация файлов
sync_files() {
    log "Запуск синхронизации (тип: $SOURCE_TYPE, источник: $SOURCE_PATH)"
    
    # Получаем список файлов и их количество
    local source_file_count=$(get_file_list "$SOURCE_TYPE" "$SOURCE_PATH")
    if [ -z "$source_file_count" ] || [ "$source_file_count" -eq 0 ]; then
        log "ПРЕДУПРЕЖДЕНИЕ: В источнике не найдено файлов"
        return 0
    fi
    
    # Создание резервной копии
    backup_old_files
    
    # Подсчет файлов до синхронизации
    local files_before=0
    if [ -d "$DEST_DIR" ]; then
        files_before=$(find "$DEST_DIR" -type f | wc -l)
    fi
    
    log "Файлов в локальном каталоге до синхронизации: $files_before"
    
    # Выполняем синхронизацию в зависимости от типа источника
    local synced_count=0
    if [ "$SOURCE_TYPE" = "local" ]; then
        synced_count=$(sync_local_files)
    elif [ "$SOURCE_TYPE" = "remote" ]; then
        synced_count=$(sync_remote_files)
    fi
    
    # Логируем итоговое состояние
    local total_files=$(find "$DEST_DIR" -type f | wc -l)
    log "ИТОГО: Файлов в локальном каталоге: $total_files"
    
    return 0
}

# Синхронизация локальных файлов
sync_local_files() {
    log "Начало синхронизации локальных файлов"
    local copied_count=0
    
    # Используем rsync если доступен (более эффективно)
    if command -v rsync > /dev/null; then
        log "Используется rsync для копирования"
        rsync -av "$SOURCE_PATH/" "$DEST_DIR/" >> "$LOG_FILE" 2>&1
        copied_count=$(find "$DEST_DIR" -type f | wc -l)
    else
        # Используем cp как fallback
        log "Используется cp для копирования"
        cp -r "$SOURCE_PATH"/* "$DEST_DIR/" 2>> "$LOG_FILE"
        copied_count=$(find "$DEST_DIR" -type f | wc -l)
    fi
    
    local files_after=$(find "$DEST_DIR" -type f | wc -l)
    local new_files=$((files_after - files_before))
    
    log "Скопировано файлов: $new_files"
    echo "$new_files"
}

# Синхронизация удаленных файлов
sync_remote_files() {
    log "Начало скачивания файлов с удаленного источника"
    local downloaded_count=0
    
    if command -v wget > /dev/null; then
        log "Используется wget для скачивания"
        wget -r -np -nH -nd -P "$DEST_DIR" \
             --progress=dot:giga \
             "$SOURCE_PATH" >> "$LOG_FILE" 2>&1
        
        if [ $? -eq 0 ]; then
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
    
    echo "$downloaded_count"
}

# Очистка временных файлов
cleanup_temp() {
    rm -rf "$TEMP_DIR"/* 2>/dev/null
    log "Временные файлы очищены"
}

# Очистка старых логов и резервных копий
cleanup() {
    # Очистка логов
    if [ -d "$(dirname "$LOG_FILE")" ]; then
        find "$(dirname "$LOG_FILE")" -name "$(basename "$LOG_FILE")*" \
             -type f -mtime +$MAX_AGE_DAYS -delete 2>/dev/null
    fi
    
    # Очистка старых резервных копий (старше 7 дней)
    if [ -d "$BACKUP_DIR" ]; then
        local backup_count=$(find "$BACKUP_DIR" -type d -name "backup_*" | wc -l)
        if [ $backup_count -gt 5 ]; then
            find "$BACKUP_DIR" -type d -name "backup_*" -exec ls -dt {} + | \
            tail -n +6 | xargs rm -rf 2>/dev/null
            log "Удалены старые резервные копии (оставлено 5 последних)"
        fi
    fi
    
    cleanup_temp
}

# Основной код
main() {
    # Загружаем конфигурацию ДО создания директорий
    load_config
    create_directories
    
    log "=== Начало выполнения скрипта ==="
    log "Тип источника: $SOURCE_TYPE"
    log "Источник: $SOURCE_PATH"
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

main "$@"