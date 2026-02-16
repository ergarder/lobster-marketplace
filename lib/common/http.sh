#!/bin/bash
# HTTP клиент с retry logic и обработкой ошибок

# Retry конфигурация
MAX_RETRIES=3
RETRY_DELAY=2

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
        local response=$(curl -s -w "\n%{http_code}" -X "$method" \
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
                    local wait_time=$((RETRY_DELAY * attempt * 10))
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
                echo "ERROR: Не удалось подключиться к Ozon API" >&2
                echo "Проверьте подключение к интернету" >&2
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
