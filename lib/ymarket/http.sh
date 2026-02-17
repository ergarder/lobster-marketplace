#!/bin/bash
# Yandex Market Partner API HTTP клиент
# Особенности: HTTP 420 for rate limits, businessId/campaignId in paths

YM_BASE_URL="https://api.partner.market.yandex.ru"

# Выполнить HTTP запрос к Yandex Market API
# Args:
#   $1 - HTTP метод (GET, POST, PUT)
#   $2 - endpoint template (e.g. /v2/businesses/{businessId}/offer-prices)
#   $3 - JSON данные (опционально)
#   $4 - id_type: "business" or "campaign" (для подстановки в path)
#   $5 - id_value (опционально, берётся из env если пусто)
ymarket_request() {
    local method=$1
    local endpoint=$2
    local data=${3:-"{}"}
    local id_type=${4:-""}
    local id_value=${5:-""}
    local attempt=1

    if [[ -z "$YM_API_KEY" ]]; then
        echo "ERROR: Яндекс Маркет API ключ не настроен. Запустите: mp-setup --platform ymarket" >&2
        return 1
    fi

    # Подставить ID в path
    if [[ "$id_type" == "business" ]]; then
        local bid="${id_value:-$YM_BUSINESS_ID}"
        [[ -z "$bid" ]] && echo "ERROR: YM_BUSINESS_ID не установлен" >&2 && return 1
        endpoint="${endpoint//\{businessId\}/$bid}"
    elif [[ "$id_type" == "campaign" ]]; then
        local cid="${id_value:-$YM_CAMPAIGN_ID}"
        [[ -z "$cid" ]] && echo "ERROR: YM_CAMPAIGN_ID не установлен" >&2 && return 1
        endpoint="${endpoint//\{campaignId\}/$cid}"
    fi

    while [ $attempt -le $MAX_RETRIES ]; do
        local curl_args=(-s --max-time "$HTTP_TIMEOUT" --connect-timeout "$HTTP_CONNECT_TIMEOUT" \
            -w "\n%{http_code}" -X "$method" \
            "${YM_BASE_URL}${endpoint}" \
            -H "Api-Key: $YM_API_KEY" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json")

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
                echo "ERROR: Неверный YM API ключ (401)" >&2
                return 1
                ;;
            403)
                echo "ERROR: YM доступ запрещён (403). Проверьте scope токена." >&2
                return 1
                ;;
            404)
                echo "ERROR: YM 404. Проверьте businessId/campaignId." >&2
                echo "$body" >&2
                return 1
                ;;
            420)
                # Yandex Market uses 420 for rate limits (not 429!)
                echo "WARNING: YM rate limit (420 Enhance Your Calm)" >&2
                if [ $attempt -lt $MAX_RETRIES ]; then
                    local wait_time=$((5 * attempt * attempt))
                    [[ $wait_time -gt 30 ]] && wait_time=30
                    echo "Ожидание ${wait_time}s..." >&2
                    sleep $wait_time
                    ((attempt++))
                    continue
                else
                    echo "ERROR: YM rate limit exceeded" >&2
                    return 1
                fi
                ;;
            429)
                # Handle 429 too, just in case
                echo "WARNING: YM rate limit (429)" >&2
                if [ $attempt -lt $MAX_RETRIES ]; then
                    sleep $((5 * attempt))
                    ((attempt++))
                    continue
                else
                    return 1
                fi
                ;;
            500|502|503)
                echo "WARNING: YM API ошибка ($http_code)" >&2
                if [ $attempt -lt $MAX_RETRIES ]; then
                    sleep $((RETRY_DELAY * attempt))
                    ((attempt++))
                    continue
                else
                    echo "ERROR: YM API недоступен" >&2
                    return 1
                fi
                ;;
            000)
                echo "ERROR: Нет подключения к YM API" >&2
                return 1
                ;;
            *)
                echo "ERROR: YM HTTP $http_code" >&2
                echo "$body" >&2
                return 1
                ;;
        esac
    done
    return 1
}
