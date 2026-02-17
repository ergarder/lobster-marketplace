#!/bin/bash
# HTTP клиент — общие функции (platform-agnostic)

# Retry конфигурация
MAX_RETRIES=3
RETRY_DELAY=2

# Timeout конфигурация
HTTP_TIMEOUT=${HTTP_TIMEOUT:-30}
HTTP_CONNECT_TIMEOUT=${HTTP_CONNECT_TIMEOUT:-10}

# Batch конфигурация
BATCH_SIZE=${BATCH_SIZE:-10}
BATCH_DELAY=${BATCH_DELAY:-1}

# Диспетчер: вызвать HTTP клиент текущей платформы
# Args: $1 method, $2 endpoint, $3 data, $4+ platform-specific
platform_request() {
    local platform="${CURRENT_PLATFORM:-ozon}"
    case "$platform" in
        ozon)    ozon_request "$@" ;;
        wb)      wb_request "$@" ;;
        ymarket) ymarket_request "$@" ;;
        *)
            echo "ERROR: Нет HTTP клиента для платформы: $platform" >&2
            return 1
            ;;
    esac
}

# Выполнить запрос с mock данными
# Args: $1 - путь к mock файлу
mock_request() {
    local mock_file=$1
    if [[ ! -f "$mock_file" ]]; then
        echo "ERROR: Mock файл не найден: $mock_file" >&2
        return 1
    fi
    cat "$mock_file"
    return 0
}

# Batch execute: выполнить функцию для массива элементов с rate limiting
# Args:
#   $1 - имя функции
#   $2 - items (newline-separated) или "-" для stdin
#   $3 - chunk_size
#   $4 - delay_sec
batch_execute() {
    local func="$1"
    local items="$2"
    local chunk_size="${3:-$BATCH_SIZE}"
    local delay_sec="${4:-$BATCH_DELAY}"

    if [[ "$items" == "-" ]]; then
        items=$(cat)
    fi

    local total=$(echo "$items" | wc -l)
    local processed=0
    local failed=0
    local chunk_num=0
    local total_chunks=$(( (total + chunk_size - 1) / chunk_size ))

    while IFS= read -r item; do
        ((processed++))

        if [[ $processed -gt 1 ]] && [[ $(( (processed - 1) % chunk_size )) -eq 0 ]]; then
            ((chunk_num++))
            echo "[${processed}/${total}] Processing batch $((chunk_num + 1))/${total_chunks}... (waiting ${delay_sec}s)" >&2
            sleep "$delay_sec"
        fi

        if ! $func "$item"; then
            ((failed++))
            echo "ERROR: Ошибка при обработке: $item" >&2
            echo "" >&2
            echo "Обработано: $((processed - failed)) успешно, $failed с ошибкой из $total" >&2
            read -p "Продолжить обработку? (y/N): " cont
            if [[ ! "$cont" =~ ^[Yy]$ ]]; then
                echo "Остановлено. Обработано: $processed/$total" >&2
                return 1
            fi
        fi

        if [[ $(( processed % chunk_size )) -eq 0 ]] || [[ $processed -eq $total ]]; then
            local eta=$(( (total - processed) / chunk_size * delay_sec ))
            echo "[${processed}/${total}] Обработано... ETA: ${eta}s" >&2
        fi
    done <<< "$items"

    echo "Batch завершён: $((processed - failed))/$total успешно" >&2
    [[ $failed -eq 0 ]]
}
