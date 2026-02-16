#!/bin/bash
# Управление ценами товаров Ozon

# Получить цену товара
# Args:
#   $1 - SKU или offer_id товара
#   --mock - использовать mock данные
get_price() {
    local sku=$1
    local mock_mode=false
    
    shift
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mock)
                mock_mode=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    
    if [[ -z "$sku" ]]; then
        echo "ERROR: SKU обязателен" >&2
        return 1
    fi
    
    log_debug "get_price called with sku=$sku mock=$mock_mode"
    
    # Mock режим
    if [[ "$mock_mode" == "true" ]]; then
        cat <<EOF
{
  "result": {
    "items": [
      {
        "offer_id": "$sku",
        "product_id": 123456,
        "price": {
          "price": "1999",
          "old_price": "2499",
          "premium_price": "1899",
          "min_price": "1500",
          "currency_code": "RUB"
        },
        "commissions": {
          "sales_percent": 8.0
        }
      }
    ]
  }
}
EOF
        return 0
    fi
    
    # Реальный API запрос
    local request_data=$(cat <<EOF
{
  "filter": {
    "offer_id": ["$sku"],
    "visibility": "ALL"
  }
}
EOF
)
    
    ozon_request "POST" "/v4/product/info/prices" "$request_data"
}

# Обновить цену товара
# Args:
#   $1 - SKU или offer_id товара
#   $2 - новая цена
#   --mock - использовать mock данные (не выполнять реальный запрос)
#   --old-price <price> - установить старую цену (зачёркнутую)
update_price() {
    local sku=$1
    local new_price=$2
    local mock_mode=false
    local old_price=""
    local batch_id="${BATCH_ID:-}"
    local current_price_for_audit=""
    
    shift 2
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mock)
                mock_mode=true
                shift
                ;;
            --old-price)
                old_price="$2"
                shift 2
                ;;
            --batch-id)
                batch_id="$2"
                shift 2
                ;;
            --audit-old-price)
                current_price_for_audit="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    if [[ -z "$sku" ]] || [[ -z "$new_price" ]]; then
        echo "ERROR: SKU и цена обязательны" >&2
        return 1
    fi
    
    # Валидация цены
    if ! [[ "$new_price" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo "ERROR: Некорректный формат цены: $new_price" >&2
        return 1
    fi
    
    # Проверка цены на 0 (R7)
    if [[ "$new_price" == "0" ]] || [[ "$new_price" == "0.00" ]] || [[ "$new_price" == "0.0" ]]; then
        echo "ERROR: Цена не может быть 0 ₽" >&2
        return 1
    fi
    
    # Audit log: записать pending
    if [[ -n "$batch_id" ]] && type audit_log_change &>/dev/null; then
        audit_log_change "price_update" "$sku" "${current_price_for_audit:-unknown}" "$new_price" "$batch_id" "pending"
    fi
    
    log_debug "update_price called with sku=$sku new_price=$new_price mock=$mock_mode"
    
    # Mock режим
    if [[ "$mock_mode" == "true" ]]; then
        # Audit: mark success
        if [[ -n "$batch_id" ]] && type audit_update_status &>/dev/null; then
            audit_update_status "$batch_id" "$sku" "success"
        fi
        cat <<EOF
{
  "result": [
    {
      "offer_id": "$sku",
      "product_id": 123456,
      "updated": true,
      "errors": []
    }
  ]
}
EOF
        return 0
    fi
    
    # Подготовка данных для обновления
    local price_data=$(cat <<EOF
{
  "offer_id": "$sku",
  "price": "$new_price"
EOF
)
    
    # Добавить old_price если указан
    if [[ -n "$old_price" ]]; then
        price_data="${price_data}, \"old_price\": \"$old_price\""
    fi
    
    price_data="${price_data}}"
    
    # Реальный API запрос
    local request_data=$(cat <<EOF
{
  "prices": [$price_data]
}
EOF
)
    
    local response
    response=$(ozon_request "POST" "/v1/product/import/prices" "$request_data")
    local result=$?
    
    # Audit: обновить статус
    if [[ -n "$batch_id" ]] && type audit_update_status &>/dev/null; then
        if [[ $result -eq 0 ]]; then
            audit_update_status "$batch_id" "$sku" "success"
        else
            audit_update_status "$batch_id" "$sku" "fail"
        fi
    fi
    
    echo "$response"
    return $result
}

# Валидировать изменение цены (не более ±50%)
# Args:
#   $1 - старая цена
#   $2 - новая цена
# Returns: 0 если валидно, 1 если изменение слишком большое
validate_price_change() {
    local old_price=$1
    local new_price=$2
    local max_change_percent=50
    
    if [[ -z "$old_price" ]] || [[ -z "$new_price" ]]; then
        echo "ERROR: Обе цены обязательны для валидации" >&2
        return 1
    fi
    
    # Вычислить процент изменения используя awk
    local change_percent=$(awk -v old="$old_price" -v new="$new_price" 'BEGIN {printf "%.2f", ((new - old) / old) * 100}')
    local abs_change=$(echo "$change_percent" | tr -d '-')
    
    # Проверить лимит
    if (( $(awk -v abs="$abs_change" -v max="$max_change_percent" 'BEGIN {print (abs > max)}') )); then
        echo "WARNING: Изменение цены слишком большое: ${change_percent}%" >&2
        echo "Допустимый диапазон: ±${max_change_percent}%" >&2
        return 1
    fi
    
    return 0
}

# Получить массовые цены товаров
# Args:
#   --mock - использовать mock данные
#   --limit <num> - количество товаров (по умолчанию 100)
get_prices_bulk() {
    local mock_mode=false
    local limit=100
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mock)
                mock_mode=true
                shift
                ;;
            --limit)
                limit="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    log_debug "get_prices_bulk called with limit=$limit mock=$mock_mode"
    
    # Mock режим
    if [[ "$mock_mode" == "true" ]]; then
        cat <<'EOF'
{
  "result": {
    "items": [
      {
        "offer_id": "TWS-PRO-001",
        "product_id": 123456,
        "price": {
          "price": "1999",
          "old_price": "2499",
          "currency_code": "RUB"
        }
      },
      {
        "offer_id": "HOME-MINI-BLK",
        "product_id": 789012,
        "price": {
          "price": "2499",
          "old_price": "",
          "currency_code": "RUB"
        }
      },
      {
        "offer_id": "BAND5-BLACK",
        "product_id": 456789,
        "price": {
          "price": "3499",
          "old_price": "3999",
          "currency_code": "RUB"
        }
      }
    ]
  }
}
EOF
        return 0
    fi
    
    # Реальный API запрос
    local request_data=$(cat <<EOF
{
  "filter": {
    "visibility": "ALL"
  },
  "limit": $limit
}
EOF
)
    
    ozon_request "POST" "/v4/product/info/prices" "$request_data"
}
