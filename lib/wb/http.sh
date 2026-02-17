#!/bin/bash
# Wildberries HTTP клиент
# Особенности: multiple base URLs, Authorization header, 409=10x penalty

# Base URLs per API category
declare -A WB_API_HOSTS=(
    [content]="content-api.wildberries.ru"
    [marketplace]="marketplace-api.wildberries.ru"
    [statistics]="statistics-api.wildberries.ru"
    [analytics]="seller-analytics-api.wildberries.ru"
    [advert]="advert-api.wildberries.ru"
    [feedbacks]="feedbacks-api.wildberries.ru"
    [prices]="discounts-prices-api.wildberries.ru"
)

# Выполнить HTTP запрос к WB API
# Args:
#   $1 - HTTP метод (GET, POST, PUT, PATCH, DELETE)
#   $2 - endpoint (например /api/v3/orders/new)
#   $3 - JSON данные (опционально)
#   $4 - категория API (marketplace, content, prices, statistics, analytics)
wb_request() {
    local method=$1
    local endpoint=$2
    local data=${3:-"{}"}
    local category=${4:-marketplace}
    local attempt=1

    # Apply host overrides from wb.env (loaded after http.sh is sourced)
    [[ -n "${WB_HOST_CONTENT:-}" ]] && WB_API_HOSTS[content]="$WB_HOST_CONTENT"
    [[ -n "${WB_HOST_MARKETPLACE:-}" ]] && WB_API_HOSTS[marketplace]="$WB_HOST_MARKETPLACE"
    [[ -n "${WB_HOST_PRICES:-}" ]] && WB_API_HOSTS[prices]="$WB_HOST_PRICES"

    if [[ -z "$WB_API_TOKEN" ]]; then
        echo "ERROR: WB API токен не настроен. Запустите: mp-setup --platform wb" >&2
        return 1
    fi

    local host="${WB_API_HOSTS[$category]:-${WB_API_HOSTS[marketplace]}}"
    local base_url="https://${host}"

    while [ $attempt -le $MAX_RETRIES ]; do
        local curl_args=(-s --max-time "$HTTP_TIMEOUT" --connect-timeout "$HTTP_CONNECT_TIMEOUT" \
            -w "\n%{http_code}" -X "$method" \
            "${base_url}${endpoint}" \
            -H "Authorization: $WB_API_TOKEN" \
            -H "Content-Type: application/json")

        # Add body for non-GET requests
        if [[ "$method" != "GET" ]]; then
            curl_args+=(-d "$data")
        fi

        local response=$(curl "${curl_args[@]}" 2>&1)
        local http_code=$(echo "$response" | tail -n1)
        local body=$(echo "$response" | sed '$d')

        case $http_code in
            200|201|204)
                echo "$body"
                return 0
                ;;
            401)
                echo "ERROR: Неверный WB API токен (401)" >&2
                return 1
                ;;
            403)
                echo "ERROR: WB доступ запрещён (403). Проверьте категорию токена." >&2
                return 1
                ;;
            409)
                # 409 Conflict counts as 10 requests toward rate limit
                echo "WARNING: WB 409 Conflict (= 10 запросов к лимиту)" >&2
                if [ $attempt -lt $MAX_RETRIES ]; then
                    sleep 3
                    ((attempt++))
                    continue
                else
                    echo "ERROR: WB 409 Conflict" >&2
                    return 1
                fi
                ;;
            429)
                echo "WARNING: WB rate limit (429)" >&2
                if [ $attempt -lt $MAX_RETRIES ]; then
                    local wait_time=$((5 * attempt * attempt))
                    [[ $wait_time -gt 30 ]] && wait_time=30
                    echo "Ожидание ${wait_time}s..." >&2
                    sleep $wait_time
                    ((attempt++))
                    continue
                else
                    echo "ERROR: WB rate limit exceeded" >&2
                    return 1
                fi
                ;;
            500|502|503)
                echo "WARNING: WB API ошибка ($http_code)" >&2
                if [ $attempt -lt $MAX_RETRIES ]; then
                    sleep $((RETRY_DELAY * attempt))
                    ((attempt++))
                    continue
                else
                    echo "ERROR: WB API недоступен" >&2
                    return 1
                fi
                ;;
            000)
                echo "ERROR: Нет подключения к WB API" >&2
                return 1
                ;;
            *)
                echo "ERROR: WB HTTP $http_code" >&2
                echo "$body" >&2
                return 1
                ;;
        esac
    done
    return 1
}
