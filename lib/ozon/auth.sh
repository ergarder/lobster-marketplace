#!/bin/bash
# Авторизация и проверка credentials для Ozon API

CREDENTIALS_DIR="${HOME}/.openclaw/marketplace"
CREDENTIALS_FILE="${CREDENTIALS_DIR}/credentials.env"

# Загрузить credentials из файла
load_credentials() {
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        # Проверить права доступа
        local perms=$(stat -c %a "$CREDENTIALS_FILE" 2>/dev/null || stat -f %A "$CREDENTIALS_FILE" 2>/dev/null)
        if [[ "$perms" != "600" ]]; then
            log_warn "Небезопасные права доступа к credentials файлу: $perms" >&2
            echo "WARNING: Небезопасные права доступа к credentials файлу" >&2
            echo "Исправление: chmod 600 $CREDENTIALS_FILE" >&2
            chmod 600 "$CREDENTIALS_FILE" 2>/dev/null
        fi
        
        # Загрузить переменные окружения
        source "$CREDENTIALS_FILE"
        
        log_debug "Credentials loaded from $CREDENTIALS_FILE"
        return 0
    else
        log_warn "Credentials file not found: $CREDENTIALS_FILE"
        return 1
    fi
}

# Проверить наличие обязательных credentials
check_ozon_credentials() {
    if [[ -z "$OZON_API_KEY" ]] || [[ -z "$OZON_CLIENT_ID" ]]; then
        echo "ERROR: Ozon credentials не настроены" >&2
        echo "" >&2
        echo "Для настройки выполните:" >&2
        echo "  mp-setup" >&2
        echo "" >&2
        log_error "Ozon credentials not configured"
        return 1
    fi
    
    log_debug "Credentials check passed"
    return 0
}

# Сохранить credentials в файл
# Args:
#   $1 - OZON_CLIENT_ID
#   $2 - OZON_API_KEY
save_credentials() {
    local client_id=$1
    local api_key=$2
    
    # Валидация
    if [[ -z "$client_id" ]] || [[ -z "$api_key" ]]; then
        echo "ERROR: Client ID и API Key не могут быть пустыми" >&2
        return 1
    fi
    
    # Проверка формата Client ID (должен быть числом)
    if ! [[ "$client_id" =~ ^[0-9]+$ ]]; then
        echo "ERROR: Client ID должен быть числом" >&2
        return 1
    fi
    
    # Создать директорию если не существует
    mkdir -p "$CREDENTIALS_DIR"
    
    # Создать файл с credentials
    cat > "$CREDENTIALS_FILE" <<EOF
# Ozon Seller API Credentials
# Создано: $(date '+%Y-%m-%d %H:%M:%S')

OZON_CLIENT_ID=$client_id
OZON_API_KEY=$api_key

# Режим работы (production | mock)
MODE=production
EOF
    
    # Установить безопасные права доступа
    chmod 600 "$CREDENTIALS_FILE"
    
    log_info "Credentials saved to $CREDENTIALS_FILE"
    echo "✅ Credentials сохранены: $CREDENTIALS_FILE"
    
    return 0
}

# Проверить подключение к Ozon API
# Returns: 0 если успешно, 1 если ошибка
test_ozon_connection() {
    # Загрузить credentials
    if ! load_credentials; then
        echo "ERROR: Не удалось загрузить credentials" >&2
        return 1
    fi
    
    # Проверить наличие credentials
    if ! check_ozon_credentials; then
        return 1
    fi
    
    echo "🔄 Проверка подключения к Ozon API..."
    echo ""
    
    # Source http.sh для доступа к ozon_request
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    source "${script_dir}/common/http.sh"
    
    # Попытка получить информацию о компании (легкий запрос для проверки)
    local response=$(ozon_request "POST" "/v1/product/list" '{"limit": 1}')
    local result=$?
    
    if [[ $result -eq 0 ]]; then
        echo "✅ Ozon API: Подключено"
        echo "Client ID: $OZON_CLIENT_ID"
        
        # Попробовать извлечь информацию о продуктах
        local product_count=$(echo "$response" | jq -r '.result.total // 0' 2>/dev/null)
        if [[ -n "$product_count" ]] && [[ "$product_count" != "null" ]]; then
            echo "Товаров в каталоге: $product_count"
        fi
        
        log_info "Ozon API connection test successful"
        return 0
    else
        echo "❌ Не удалось подключиться к Ozon API"
        echo ""
        echo "Возможные причины:"
        echo "  • Неверный Client ID или API Key"
        echo "  • API ключ не имеет нужных прав"
        echo "  • Проблемы с подключением к интернету"
        echo ""
        echo "Проверьте credentials и повторите попытку: mp-setup"
        
        log_error "Ozon API connection test failed"
        return 1
    fi
}

# Удалить credentials
remove_credentials() {
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        rm -f "$CREDENTIALS_FILE"
        echo "✅ Credentials удалены"
        log_info "Credentials removed"
        return 0
    else
        echo "Credentials файл не найден"
        return 1
    fi
}

# Показать статус авторизации
show_auth_status() {
    if [[ ! -f "$CREDENTIALS_FILE" ]]; then
        echo "❌ Не настроено"
        echo ""
        echo "Для настройки выполните: mp-setup"
        return 1
    fi
    
    load_credentials
    
    if check_ozon_credentials; then
        echo "✅ Настроено"
        echo ""
        echo "Client ID: $OZON_CLIENT_ID"
        echo "API Key: ${OZON_API_KEY:0:10}***"
        echo "Режим: ${MODE:-production}"
        return 0
    else
        echo "❌ Некорректная конфигурация"
        return 1
    fi
}
