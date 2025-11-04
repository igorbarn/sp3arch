#!/bin/bash

# 04/11/25
# Улучшенный скрипт с поддержкой локального и удаленного источников

# Создание тестовых данных для локального источника
TEST_SOURCE="/tmp/source_files"
TEST_DEST="$HOME/sync_files"

echo "Создание тестовых данных..."

# Создаем директорию источника
mkdir -p "$TEST_SOURCE"

# Создаем тестовые файлы
for i in {1..5}; do
    echo "Это тестовый файл $i" > "$TEST_SOURCE/file_$i.txt"
    dd if=/dev/urandom of="$TEST_SOURCE/binary_$i.dat" bs=1K count=10 2>/dev/null
done

# Создаем поддиректории с файлами
mkdir -p "$TEST_SOURCE/subdir"
for i in {1..3}; do
    echo "Файл в поддиректории $i" > "$TEST_SOURCE/subdir/subfile_$i.txt"
done

echo "Тестовые данные созданы в: $TEST_SOURCE"
echo "Файлы:"
find "$TEST_SOURCE" -type f -printf "  - %P\n"

# Создаем конфигурационный файл для тестирования
mkdir -p ~/.config/http_sync
cat > ~/.config/http_sync/http_sync.conf << EOF
SOURCE_TYPE="local"
SOURCE_PATH="$TEST_SOURCE"
DEST_DIR="$TEST_DEST"
LOG_FILE="$HOME/sync_test.log"
BACKUP_OLD_FILES=true
BACKUP_DIR="$HOME/sync_test_backup"
TEMP_DIR="/tmp/sync_test_$USER"
EOF

echo "Конфигурационный файл создан: ~/.config/http_sync/http_sync.conf"
echo "Для тестирования выполните: ./http_sync.sh"