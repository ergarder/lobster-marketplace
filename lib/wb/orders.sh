#!/bin/bash
# WB заказы (FBS)
# Особенности: dateFrom/dateTo = Unix timestamps, dual status, prices in kopecks

SCRIPT_DIR_WB_ORDERS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

wb_get_orders() {
    local mock_mode=false
    local limit=100
    local date_from=""
    local date_to=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --mock) mock_mode=true; shift ;;
            --limit) limit="$2"; shift 2 ;;
            --date-from) date_from="$2"; shift 2 ;;
            --date-to) date_to="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ "$mock_mode" == "true" ]]; then
        cat <<'MOCK_EOF'
{
  "orders": [
    {
      "id": 987654321,
      "rid": "abc123def456",
      "createdAt": "2026-02-16T08:30:00Z",
      "warehouseId": 507921,
      "supplierStatus": "new",
      "wbStatus": "waiting",
      "salePrice": 504600,
      "convertedPrice": 504600,
      "currencyCode": 643,
      "convertedCurrencyCode": 643,
      "article": "TWS-PRO-001",
      "nmId": 12345678,
      "skus": ["2000000000011"]
    },
    {
      "id": 987654322,
      "rid": "abc123def457",
      "createdAt": "2026-02-16T10:15:00Z",
      "warehouseId": 507921,
      "supplierStatus": "confirm",
      "wbStatus": "sorted",
      "salePrice": 249900,
      "convertedPrice": 249900,
      "currencyCode": 643,
      "convertedCurrencyCode": 643,
      "article": "HOME-MINI-BLK",
      "nmId": 87654321,
      "skus": ["2000000000028"]
    },
    {
      "id": 987654323,
      "rid": "abc123def458",
      "createdAt": "2026-02-15T14:00:00Z",
      "warehouseId": 507922,
      "supplierStatus": "complete",
      "wbStatus": "sold",
      "salePrice": 349900,
      "convertedPrice": 349900,
      "currencyCode": 643,
      "convertedCurrencyCode": 643,
      "article": "BAND5-BLACK",
      "nmId": 11223344,
      "skus": ["2000000000035"]
    }
  ],
  "next": 987654324
}
MOCK_EOF
        return 0
    fi

    # Build query params
    local params="limit=${limit}&next=0"
    [[ -n "$date_from" ]] && params="${params}&dateFrom=${date_from}"
    [[ -n "$date_to" ]] && params="${params}&dateTo=${date_to}"

    wb_request "GET" "/api/v3/orders?${params}" "{}" "marketplace"
}

wb_get_new_orders() {
    local mock_mode=false
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mock) mock_mode=true; shift ;;
            *) shift ;;
        esac
    done

    if [[ "$mock_mode" == "true" ]]; then
        wb_get_orders --mock
        return $?
    fi

    wb_request "GET" "/api/v3/orders/new" "{}" "marketplace"
}

wb_get_order_status() {
    local order_id=$1; shift
    local mock_mode=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --mock) mock_mode=true; shift ;;
            *) shift ;;
        esac
    done

    [[ -z "$order_id" ]] && echo "ERROR: ID заказа обязателен" >&2 && return 1
    [[ ! "$order_id" =~ ^[0-9]+$ ]] && echo "ERROR: ID заказа должен быть числом" >&2 && return 1

    if [[ "$mock_mode" == "true" ]]; then
        cat <<EOF
{
  "orders": [
    {
      "id": $order_id,
      "supplierStatus": "new",
      "wbStatus": "waiting",
      "salePrice": 504600,
      "currencyCode": 643,
      "article": "TWS-PRO-001"
    }
  ]
}
EOF
        return 0
    fi

    wb_request "POST" "/api/v3/orders/status" "{\"orders\":[$order_id]}" "marketplace"
}

wb_get_orders_stats() {
    local mock_mode=false
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mock) mock_mode=true; shift ;;
            *) shift ;;
        esac
    done

    local orders_json=$(wb_get_orders ${mock_mode:+--mock})
    [[ -z "$orders_json" ]] && echo "ERROR: Нет данных" >&2 && return 1

    local total=$(echo "$orders_json" | jq -r '.orders | length')
    local new_count=$(echo "$orders_json" | jq -r '[.orders[] | select(.supplierStatus == "new")] | length')
    local confirm=$(echo "$orders_json" | jq -r '[.orders[] | select(.supplierStatus == "confirm")] | length')

    cat <<EOF
{
  "total": $total,
  "by_status": {
    "new": $new_count,
    "confirm": $confirm
  }
}
EOF
}
