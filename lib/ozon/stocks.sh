#!/bin/bash
# Управление остатками товаров Ozon

# Получить остатки товаров
# Args:
#   --mock - использовать mock данные
#   --low - только товары с низкими остатками (< 10)
#   --warehouse <id> - фильтр по складу
#   --limit <num> - количество товаров (по умолчанию 100)
get_stocks() {
    local mock_mode=false
    local low_stocks_only=false
    local warehouse_id=""
    local limit=100
    
    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mock)
                mock_mode=true
                shift
                ;;
            --low)
                low_stocks_only=true
                shift
                ;;
            --warehouse)
                warehouse_id="$2"
                shift 2
                ;;
            --limit)
                if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    echo "ERROR: --limit должен быть числом: $2" >&2; return 1
                fi
                limit="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    log_debug "get_stocks called with low=$low_stocks_only warehouse=$warehouse_id limit=$limit mock=$mock_mode"
    
    # Mock режим
    if [[ "$mock_mode" == "true" ]]; then
        cat <<'EOF'
{
  "result": {
    "rows": [
      {
        "sku": 123456,
        "offer_id": "TWS-PRO-001",
        "name": "Беспроводные наушники TWS Pro",
        "stock": 45,
        "reserved": 5,
        "warehouse_name": "Склад Москва",
        "warehouse_id": 12345
      },
      {
        "sku": 789012,
        "offer_id": "HOME-MINI-BLK",
        "name": "Умная колонка Home Mini",
        "stock": 8,
        "reserved": 2,
        "warehouse_name": "Склад Москва",
        "warehouse_id": 12345
      },
      {
        "sku": 456789,
        "offer_id": "BAND5-BLACK",
        "name": "Фитнес-браслет Smart Band 5",
        "stock": 3,
        "reserved": 0,
        "warehouse_name": "Склад Санкт-Петербург",
        "warehouse_id": 67890
      },
      {
        "sku": 111222,
        "offer_id": "MOUSE-WIRELESS",
        "name": "Беспроводная мышь Pro",
        "stock": 120,
        "reserved": 10,
        "warehouse_name": "Склад Москва",
        "warehouse_id": 12345
      },
      {
        "sku": 333444,
        "offer_id": "KEYBOARD-MINI",
        "name": "Компактная клавиатура",
        "stock": 0,
        "reserved": 0,
        "warehouse_name": "Склад Москва",
        "warehouse_id": 12345
      }
    ]
  }
}
EOF
        return 0
    fi
    
    # Реальный API запрос
    local request_data
    if [[ -n "$warehouse_id" ]]; then
        request_data=$(jq -n --argjson limit "$limit" --arg wh "$warehouse_id" \
            '{limit:$limit,filter:{visibility:"ALL",warehouse_id:$wh}}')
    else
        request_data=$(jq -n --argjson limit "$limit" '{limit:$limit,filter:{visibility:"ALL"}}')
    fi

    ozon_request "POST" "/v4/product/info/stocks" "$request_data"
}

# Обновить остаток товара
# Args:
#   $1 - SKU или offer_id товара
#   $2 - новое количество
#   --mock - использовать mock данные
#   --warehouse <id> - ID склада (опционально)
update_stock() {
    local sku=$1
    local new_quantity=$2
    local mock_mode=false
    local warehouse_id=""
    local batch_id="${BATCH_ID:-}"
    local current_stock_for_audit=""
    
    shift 2
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mock)
                mock_mode=true
                shift
                ;;
            --warehouse)
                warehouse_id="$2"
                shift 2
                ;;
            --batch-id)
                batch_id="$2"
                shift 2
                ;;
            --audit-old-stock)
                current_stock_for_audit="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    if [[ -z "$sku" ]] || [[ -z "$new_quantity" ]]; then
        echo "ERROR: SKU и количество обязательны" >&2
        return 1
    fi
    
    # Explicit negative check (defense-in-depth, R7)
    if [[ "$new_quantity" =~ ^- ]]; then
        echo "ERROR: Количество не может быть отрицательным: $new_quantity" >&2
        return 1
    fi
    
    # Валидация количества
    if ! [[ "$new_quantity" =~ ^[0-9]+$ ]]; then
        echo "ERROR: Количество должно быть целым числом: $new_quantity" >&2
        return 1
    fi
    
    # Предупреждение при stock=0 (R7)
    if [[ "$new_quantity" == "0" ]]; then
        echo "⚠️ WARNING: Установка остатка в 0 отключит товар на площадке!" >&2
        if [[ "${AUTO_CONFIRM_ZERO:-false}" != "true" ]]; then
            read -p "Продолжить? (y/N): " confirm_zero
            [[ ! "$confirm_zero" =~ ^[Yy]$ ]] && return 1
        fi
    fi
    
    # Audit log: записать pending
    if [[ -n "$batch_id" ]] && type audit_log_change &>/dev/null; then
        audit_log_change "stock_update" "$sku" "${current_stock_for_audit:-unknown}" "$new_quantity" "$batch_id" "pending"
    fi
    
    log_debug "update_stock called with sku=$sku quantity=$new_quantity warehouse=$warehouse_id mock=$mock_mode"
    
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
    local stock_data
    if [[ -n "$warehouse_id" ]]; then
        stock_data=$(jq -n --arg sku "$sku" --argjson qty "$new_quantity" --argjson wh "$warehouse_id" \
            '{offer_id:$sku,stock:$qty,warehouse_id:$wh}')
    else
        stock_data=$(jq -n --arg sku "$sku" --argjson qty "$new_quantity" \
            '{offer_id:$sku,stock:$qty}')
    fi

    # Реальный API запрос
    local request_data
    request_data=$(jq -n --argjson sd "$stock_data" '{stocks:[$sd]}')
    
    local response
    response=$(ozon_request "POST" "/v1/product/import/stocks" "$request_data")
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

# Получить остаток конкретного товара
# Args:
#   $1 - SKU или offer_id товара
#   --mock - использовать mock данные
get_stock_by_sku() {
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
    
    local args=()
    [[ "$mock_mode" == "true" ]] && args+=("--mock")
    
    local stocks_json
    stocks_json=$(get_stocks "${args[@]}") || return 1
    
    if [[ "$mock_mode" == "true" ]]; then
        echo "$stocks_json" | jq --arg sku "$sku" '.result.rows[] | select(.offer_id == $sku or (.sku|tostring) == $sku)'
        return 0
    fi
    
    echo "$stocks_json" | jq --arg sku "$sku" '
        .items[]
        | select(.offer_id == $sku or (.product_id|tostring) == $sku)
        | . as $item
        | (([.stocks[]? | select(.type=="fbo") | .present] | add) // 0) as $present
        | (([.stocks[]? | select(.type=="fbo") | .reserved] | add) // 0) as $reserved
        | {
            sku: $item.offer_id,
            offer_id: $item.offer_id,
            product_id: $item.product_id,
            stock: $present,
            reserved: $reserved,
            type: "fbo"
        }
    '
}

# Проверить товары с низкими остатками
# Args:
#   --mock - использовать mock данные
#   --threshold <num> - порог низкого остатка (по умолчанию 10)
check_low_stocks() {
    local threshold=10
    local mock_mode=false
    local args=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --threshold)
                threshold="$2"
                shift 2
                ;;
            --mock)
                mock_mode=true
                args+=("--mock")
                shift
                ;;
            --limit)
                args+=("$1" "$2")
                shift 2
                ;;
            --warehouse)
                args+=("$1" "$2")
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    log_debug "check_low_stocks called with threshold=$threshold mock=$mock_mode"
    
    local stocks_json
    stocks_json=$(get_stocks "${args[@]}") || return 1
    
    if [[ "$mock_mode" == "true" ]]; then
        echo "$stocks_json" | jq --argjson thresh "$threshold" '{
            result: {
                rows: [.result.rows[] | select(.stock < $thresh)]
            }
        }'
        return 0
    fi
    
    echo "$stocks_json" | jq --argjson thresh "$threshold" '{
        items: [
            .items[]
            | . as $item
            | (([.stocks[]? | select(.type=="fbo") | .present] | add) // 0) as $present
            | select($present < $thresh)
        ],
        total: (
            [
                .items[]
                | (([.stocks[]? | select(.type=="fbo") | .present] | add) // 0) as $present
                | select($present < $thresh)
            ] | length
        ),
        cursor: (.cursor // "")
    }'
}
