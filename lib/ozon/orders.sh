#!/bin/bash
# Управление заказами Ozon

# Получить список заказов
# Args:
#   --mock - использовать mock данные
#   --status <status> - фильтр по статусу (awaiting_packaging, delivering, delivered)
#   --limit <num> - количество заказов (по умолчанию 50)
get_orders() {
    local mock_mode=false
    local status="awaiting_packaging"
    local limit=50
    
    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mock)
                mock_mode=true
                shift
                ;;
            --status)
                status="$2"
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

    log_debug "get_orders called with status=$status limit=$limit mock=$mock_mode"
    
    # Mock режим
    if [[ "$mock_mode" == "true" ]]; then
        cat <<'EOF'
{
  "result": {
    "postings": [
      {
        "posting_number": "12345678-0001-1",
        "order_id": 123456789,
        "order_number": "12345678-0001",
        "status": "awaiting_packaging",
        "shipment_date": "2026-02-17T12:00:00Z",
        "in_process_at": "2026-02-16T08:30:00Z",
        "warehouse_name": "Склад Москва",
        "products": [
          {
            "sku": 123456,
            "name": "Беспроводные наушники TWS Pro",
            "quantity": 2,
            "price": "1999.00",
            "offer_id": "TWS-PRO-001"
          }
        ]
      },
      {
        "posting_number": "12345678-0002-1",
        "order_id": 123456790,
        "order_number": "12345678-0002",
        "status": "awaiting_packaging",
        "shipment_date": "2026-02-16T18:00:00Z",
        "in_process_at": "2026-02-16T10:15:00Z",
        "warehouse_name": "Склад Санкт-Петербург",
        "products": [
          {
            "sku": 789012,
            "name": "Умная колонка Home Mini",
            "quantity": 1,
            "price": "2499.00",
            "offer_id": "HOME-MINI-BLK"
          },
          {
            "sku": 789013,
            "name": "Кабель USB-C 2м",
            "quantity": 3,
            "price": "299.00",
            "offer_id": "USBC-CABLE-2M"
          }
        ]
      },
      {
        "posting_number": "12345678-0003-1",
        "order_id": 123456791,
        "order_number": "12345678-0003",
        "status": "delivering",
        "shipment_date": "2026-02-15T14:00:00Z",
        "in_process_at": "2026-02-14T09:00:00Z",
        "warehouse_name": "Склад Москва",
        "products": [
          {
            "sku": 456789,
            "name": "Фитнес-браслет Smart Band 5",
            "quantity": 1,
            "price": "3499.00",
            "offer_id": "BAND5-BLACK"
          }
        ]
      }
    ]
  }
}
EOF
        return 0
    fi
    
    # Реальный API запрос
    local request_data
    if [[ "$status" == "all" ]]; then
        request_data=$(jq -n --argjson limit "$limit" \
            '{filter:{},limit:$limit,with:{analytics_data:true,financial_data:false}}')
    else
        request_data=$(jq -n \
            --arg status "$status" \
            --argjson limit "$limit" \
            '{filter:{status:$status},limit:$limit,with:{analytics_data:true,financial_data:false}}')
    fi

    ozon_request "POST" "/v3/posting/fbs/list" "$request_data"
}

# Получить статус заказа
# Args:
#   $1 - posting_number (номер отправления)
#   --mock - использовать mock данные
get_order_status() {
    local posting_number=$1
    local mock_mode=false
    
    # Парсинг аргументов
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
    
    if [[ -z "$posting_number" ]]; then
        echo "ERROR: posting_number обязателен" >&2
        return 1
    fi
    
    log_debug "get_order_status called with posting_number=$posting_number mock=$mock_mode"
    
    # Mock режим
    if [[ "$mock_mode" == "true" ]]; then
        cat <<EOF
{
  "result": {
    "posting_number": "$posting_number",
    "order_id": 123456789,
    "order_number": "12345678-0001",
    "status": "awaiting_packaging",
    "shipment_date": "2026-02-17T12:00:00Z",
    "in_process_at": "2026-02-16T08:30:00Z",
    "warehouse_name": "Склад Москва",
    "delivery_method": {
      "name": "Доставка курьером",
      "warehouse": "Москва"
    },
    "products": [
      {
        "sku": 123456,
        "name": "Беспроводные наушники TWS Pro",
        "quantity": 2,
        "price": "1999.00",
        "offer_id": "TWS-PRO-001"
      }
    ],
    "customer": {
      "address": {
        "city": "Москва"
      }
    }
  }
}
EOF
        return 0
    fi
    
    # Реальный API запрос
    local request_data
    request_data=$(jq -n --arg pn "$posting_number" \
        '{posting_number:$pn,with:{analytics_data:true,financial_data:true}}')

    ozon_request "POST" "/v3/posting/fbs/get" "$request_data"
}

# Получить статистику заказов
# Args:
#   --mock - использовать mock данные
get_orders_stats() {
    local mock_mode=false
    
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
    
    log_debug "get_orders_stats called with mock=$mock_mode"
    
    # Получить заказы (mock возвращает все статусы; production тоже без фильтра)
    local orders_json=$(get_orders --status all ${mock_mode:+--mock})
    
    if [[ -z "$orders_json" ]]; then
        echo "ERROR: Не удалось получить данные о заказах" >&2
        return 1
    fi
    
    # Подсчитать статистику
    local total=$(echo "$orders_json" | jq -r '.result.postings | length')
    local awaiting=$(echo "$orders_json" | jq -r '.result.postings | map(select(.status == "awaiting_packaging")) | length')
    local delivering=$(echo "$orders_json" | jq -r '.result.postings | map(select(.status == "delivering")) | length')
    
    cat <<EOF
{
  "total": $total,
  "by_status": {
    "awaiting_packaging": $awaiting,
    "delivering": $delivering
  }
}
EOF
}
