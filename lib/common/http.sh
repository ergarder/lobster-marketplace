#!/bin/bash
# HTTP клиент с retry logic и обработкой ошибок

# Retry конфигурация
MAX_RETRIES=3
RETRY_DELAY=2

# Timeout конфигурация (R6)
HTTP_TIMEOUT=${HTTP_TIMEOUT:-30}
HTTP_CONNECT_TIMEOUT=${HTTP_CONNECT_TIMEOUT:-10}

# Batch конфигурация (R3)
BATCH_SIZE=${BATCH_SIZE:-10}
BATCH_DELAY=${BATCH_DELAY:-1}

# Выполнить HTTP запрос к Ozon API
# Args:
#   $1 - HTTP метод (GET, POST, PUT)
#   $2 - endpoint (например /v3/posting/fbs/list)
#   $3 - JSON данные для POST/PUT (опционально)
ozon_request() {
    local method=$1
    local endpoint=$2
    local data=${3:-"{}"}
    local attempt=1
    
    # Проверка credentials
    if [[ -z "$OZON_API_KEY" ]] || [[ -z "$OZON_CLIENT_ID" ]]; then
        echo "ERROR: Ozon credentials не настроены. Запустите: mp-setup" >&2
        return 1
    fi
    
    while [ $attempt -le $MAX_RETRIES ]; do
        # Выполнить запрос
        local response=$(curl -s --max-time "$HTTP_TIMEOUT" --connect-timeout "$HTTP_CONNECT_TIMEOUT" \
            -w "\n%{http_code}" -X "$method" \
            "https://api-seller.ozon.ru$endpoint" \
            -H "Client-Id: $OZON_CLIENT_ID" \
            -H "Api-Key: $OZON_API_KEY" \
            -H "Content-Type: application/json" \
            -d "$data" 2>&1)
        
        local http_code=$(echo "$response" | tail -n1)
        local body=$(echo "$response" | sed '$d')
        
        # Обработка HTTP статусов
        case $http_code in
            200|201)
                echo "$body"
                return 0
                ;;
            401)
                echo "ERROR: Неверные API credentials (401)" >&2
                echo "Проверьте OZON_CLIENT_ID и OZON_API_KEY" >&2
                echo "Запустите: mp-setup" >&2
                return 1
                ;;
            403)
                echo "ERROR: Доступ запрещён (403)" >&2
                echo "API ключ не имеет нужных прав" >&2
                echo "Создайте новый ключ с правами Admin или Content+Analytics" >&2
                return 1
                ;;
            429)
                echo "WARNING: Превышен лимит запросов (429)" >&2
                if [ $attempt -lt $MAX_RETRIES ]; then
                    # Exponential backoff: 5s, 15s, 30s
                    local wait_time=$((5 * attempt * attempt))
                    [[ $wait_time -gt 30 ]] && wait_time=30
                    echo "Ожидание ${wait_time} секунд перед повтором..." >&2
                    sleep $wait_time
                    ((attempt++))
                    continue
                else
                    echo "ERROR: Превышен лимит запросов. Подождите 60 секунд и повторите." >&2
                    return 1
                fi
                ;;
            500|502|503)
                echo "WARNING: Ozon API ошибка ($http_code)" >&2
                if [ $attempt -lt $MAX_RETRIES ]; then
                    local wait_time=$((RETRY_DELAY * attempt))
                    echo "Повтор через ${wait_time} секунд... (попытка $attempt/$MAX_RETRIES)" >&2
                    sleep $wait_time
                    ((attempt++))
                    continue
                else
                    echo "ERROR: Ozon API недоступен. Повторите позже." >&2
                    return 1
                fi
                ;;
            000)
                echo "ERROR: Не удалось подключиться к Ozon API (timeout или нет сети)" >&2
                echo "Проверьте подключение к интернету (timeout: ${HTTP_TIMEOUT}s)" >&2
                return 1
                ;;
            *)
                echo "ERROR: Неожиданный HTTP статус $http_code" >&2
                echo "$body" >&2
                return 1
                ;;
        esac
    done
    
    return 1
}

# Выполнить запрос с mock данными (для тестирования)
# Args:
#   $1 - путь к mock файлу
mock_request() {
    local mock_file=$1
    
    if [[ ! -f "$mock_file" ]]; then
        echo "ERROR: Mock файл не найден: $mock_file" >&2
        return 1
    fi
    
    cat "$mock_file"
    return 0
}

# Batch execute: выполнить функцию для массива элементов с rate limiting (R3)
# Args:
#   $1 - имя функции для вызова (получает один item как аргумент)
#   $2 - массив items (newline-separated)
#   $3 - chunk_size (по умолчанию $BATCH_SIZE=10)
#   $4 - delay_sec (по умолчанию $BATCH_DELAY=1)
# Stdin: items (one per line) if $2 is "-"
# Returns: 0 if all succeeded, 1 if any failed
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
        
        # Chunk boundary: delay between chunks
        if [[ $processed -gt 1 ]] && [[ $(( (processed - 1) % chunk_size )) -eq 0 ]]; then
            ((chunk_num++))
            echo "[${processed}/${total}] Processing batch $((chunk_num + 1))/${total_chunks}... (waiting ${delay_sec}s)" >&2
            sleep "$delay_sec"
        fi
        
        # Execute function for this item
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
        
        # Progress (every chunk_size items)
        if [[ $(( processed % chunk_size )) -eq 0 ]] || [[ $processed -eq $total ]]; then
            local eta=$(( (total - processed) / chunk_size * delay_sec ))
            echo "[${processed}/${total}] Обработано... ETA: ${eta}s" >&2
        fi
    done <<< "$items"
    
    echo "Batch завершён: $((processed - failed))/$total успешно" >&2
    [[ $failed -eq 0 ]]
}
