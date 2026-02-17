#!/bin/bash
# WB авторизация и credentials

CREDENTIALS_DIR="${HOME}/.openclaw/marketplace"
WB_CREDENTIALS_FILE="${CREDENTIALS_DIR}/wb.env"

load_wb_credentials() {
    if [[ -f "$WB_CREDENTIALS_FILE" ]]; then
        local perms=$(stat -c %a "$WB_CREDENTIALS_FILE" 2>/dev/null || stat -f %A "$WB_CREDENTIALS_FILE" 2>/dev/null)
        if [[ "$perms" != "600" ]]; then
            chmod 600 "$WB_CREDENTIALS_FILE" 2>/dev/null
        fi
        source "$WB_CREDENTIALS_FILE"
        return 0
    fi
    return 1
}

check_wb_credentials() {
    if [[ -z "$WB_API_TOKEN" ]]; then
        echo "ERROR: WB API токен не настроен" >&2
        echo "Запустите: mp-setup --platform wb" >&2
        return 1
    fi
    if [[ ${#WB_API_TOKEN} -lt 20 ]]; then
        echo "ERROR: WB API токен слишком короткий" >&2
        return 1
    fi
    return 0
}

save_wb_credentials() {
    local token=$1
    [[ -z "$token" ]] && echo "ERROR: Токен не может быть пустым" >&2 && return 1

    mkdir -p "$CREDENTIALS_DIR"
    cat > "$WB_CREDENTIALS_FILE" <<EOF
# Wildberries Seller API Credentials
# Создано: $(date '+%Y-%m-%d %H:%M:%S')

WB_API_TOKEN=$token

# Режим работы
WB_MODE=production

# Переопределение хостов (опционально)
# WB_HOST_CONTENT=content-api.wildberries.ru
# WB_HOST_MARKETPLACE=marketplace-api.wildberries.ru
# WB_HOST_PRICES=discounts-prices-api.wildberries.ru
EOF
    chmod 600 "$WB_CREDENTIALS_FILE"
    echo "✅ WB credentials сохранены: $WB_CREDENTIALS_FILE"
    return 0
}

test_wb_connection() {
    echo "🔄 Проверка подключения к WB API..."
    local response=$(wb_request "GET" "/api/v3/warehouses" "{}" "marketplace")
    local result=$?

    if [[ $result -eq 0 ]]; then
        echo "✅ WB API: Подключено"
        local wh_count=$(echo "$response" | jq 'length' 2>/dev/null)
        [[ -n "$wh_count" ]] && echo "Складов: $wh_count"
        return 0
    else
        echo "❌ Не удалось подключиться к WB API"
        return 1
    fi
}

show_wb_auth_status() {
    if [[ ! -f "$WB_CREDENTIALS_FILE" ]]; then
        echo "❌ WB: Не настроено"
        return 1
    fi
    load_wb_credentials
    if check_wb_credentials 2>/dev/null; then
        echo "✅ WB: Настроено"
        echo "  Token: ${WB_API_TOKEN:0:15}***"
        echo "  Режим: ${WB_MODE:-production}"
        return 0
    fi
    echo "❌ WB: Некорректная конфигурация"
    return 1
}
