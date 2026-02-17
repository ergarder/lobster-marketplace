#!/bin/bash
# Yandex Market авторизация
# Особенности: businessId vs campaignId, token scope delay ~10min

CREDENTIALS_DIR="${HOME}/.openclaw/marketplace"
YM_CREDENTIALS_FILE="${CREDENTIALS_DIR}/ymarket.env"

load_ym_credentials() {
    if [[ -f "$YM_CREDENTIALS_FILE" ]]; then
        local perms=$(stat -c %a "$YM_CREDENTIALS_FILE" 2>/dev/null || stat -f %A "$YM_CREDENTIALS_FILE" 2>/dev/null)
        [[ "$perms" != "600" ]] && chmod 600 "$YM_CREDENTIALS_FILE" 2>/dev/null
        source "$YM_CREDENTIALS_FILE"
        return 0
    fi
    return 1
}

check_ym_credentials() {
    if [[ -z "$YM_API_KEY" ]]; then
        echo "ERROR: Яндекс Маркет API ключ не настроен" >&2
        echo "Запустите: mp-setup --platform ymarket" >&2
        return 1
    fi
    return 0
}

save_ym_credentials() {
    local api_key=$1
    local business_id=${2:-""}
    local campaign_id=${3:-""}

    [[ -z "$api_key" ]] && echo "ERROR: API Key не может быть пустым" >&2 && return 1

    mkdir -p "$CREDENTIALS_DIR"
    cat > "$YM_CREDENTIALS_FILE" <<EOF
# Yandex Market Partner API Credentials
# Создано: $(date '+%Y-%m-%d %H:%M:%S')
# ⚠️ Изменения scope токена вступают в силу через ~10 минут

YM_API_KEY=$api_key
YM_BUSINESS_ID=$business_id
YM_CAMPAIGN_ID=$campaign_id

# Режим работы
YM_MODE=production
EOF
    chmod 600 "$YM_CREDENTIALS_FILE"
    echo "✅ YM credentials сохранены: $YM_CREDENTIALS_FILE"
    return 0
}

# Получить businessId и campaignId из API
resolve_ym_ids() {
    echo "🔄 Получение businessId и campaignId..."
    local response=$(ymarket_request "GET" "/v2/campaigns")
    local result=$?

    if [[ $result -ne 0 ]]; then
        echo "ERROR: Не удалось получить данные кампаний" >&2
        return 1
    fi

    local business_id=$(echo "$response" | jq -r '.campaigns[0].business.id // empty' 2>/dev/null)
    local campaign_id=$(echo "$response" | jq -r '.campaigns[0].id // empty' 2>/dev/null)
    local shop_name=$(echo "$response" | jq -r '.campaigns[0].domain // "unknown"' 2>/dev/null)

    if [[ -n "$business_id" ]] && [[ -n "$campaign_id" ]]; then
        export YM_BUSINESS_ID="$business_id"
        export YM_CAMPAIGN_ID="$campaign_id"

        # Update credentials file
        if [[ -f "$YM_CREDENTIALS_FILE" ]]; then
            sed -i "s/^YM_BUSINESS_ID=.*/YM_BUSINESS_ID=$business_id/" "$YM_CREDENTIALS_FILE"
            sed -i "s/^YM_CAMPAIGN_ID=.*/YM_CAMPAIGN_ID=$campaign_id/" "$YM_CREDENTIALS_FILE"
        fi

        echo "  Business ID: $business_id"
        echo "  Campaign ID: $campaign_id"
        echo "  Магазин: $shop_name"
        return 0
    else
        echo "WARNING: Не удалось извлечь ID" >&2
        return 1
    fi
}

test_ym_connection() {
    echo "🔄 Проверка подключения к Яндекс Маркет API..."

    local response=$(ymarket_request "GET" "/v2/campaigns")
    local result=$?

    if [[ $result -eq 0 ]]; then
        echo "✅ Яндекс Маркет API: Подключено"
        local count=$(echo "$response" | jq -r '.campaigns | length' 2>/dev/null)
        [[ -n "$count" ]] && echo "Магазинов: $count"

        # Auto-resolve IDs if not set
        if [[ -z "${YM_BUSINESS_ID:-}" ]] || [[ -z "${YM_CAMPAIGN_ID:-}" ]]; then
            resolve_ym_ids
        fi
        return 0
    else
        echo "❌ Не удалось подключиться к Яндекс Маркет API"
        return 1
    fi
}

show_ym_auth_status() {
    if [[ ! -f "$YM_CREDENTIALS_FILE" ]]; then
        echo "❌ Яндекс Маркет: Не настроено"
        return 1
    fi
    load_ym_credentials
    if check_ym_credentials 2>/dev/null; then
        echo "✅ Яндекс Маркет: Настроено"
        echo "  API Key: ${YM_API_KEY:0:15}***"
        echo "  Business ID: ${YM_BUSINESS_ID:-не установлен}"
        echo "  Campaign ID: ${YM_CAMPAIGN_ID:-не установлен}"
        return 0
    fi
    echo "❌ Яндекс Маркет: Некорректная конфигурация"
    return 1
}
