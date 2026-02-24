#!/bin/bash
# Yandex Market заказы
# Особенности: businessId for list, campaignId for details, RUR currency, 100+ substatuses

ym_get_orders() {
    local mock_mode=false
    local limit=50
    local status=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --mock) mock_mode=true; shift ;;
            --limit) limit="$2"; shift 2 ;;
            --status) status="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ "$mock_mode" == "true" ]]; then
        cat <<'MOCK_EOF'
{
  "orders": [
    {
      "orderId": 77001122,
      "campaignId": 21098765,
      "programType": "FBS",
      "status": "PROCESSING",
      "substatus": "STARTED",
      "creationDate": "2026-02-16T08:30:00+03:00",
      "paymentType": "PREPAID",
      "items": [
        {
          "offerId": "TWS-PRO-001",
          "count": 2,
          "prices": {
            "payment": {"value": 1999.00, "currencyId": "RUR"}
          }
        }
      ]
    },
    {
      "orderId": 77001123,
      "campaignId": 21098765,
      "programType": "FBS",
      "status": "PROCESSING",
      "substatus": "READY_TO_SHIP",
      "creationDate": "2026-02-16T10:15:00+03:00",
      "paymentType": "PREPAID",
      "items": [
        {
          "offerId": "HOME-MINI-BLK",
          "count": 1,
          "prices": {
            "payment": {"value": 2499.00, "currencyId": "RUR"}
          }
        }
      ]
    },
    {
      "orderId": 77001124,
      "campaignId": 21098765,
      "programType": "FBS",
      "status": "DELIVERY",
      "substatus": "DELIVERY_SERVICE_RECEIVED",
      "creationDate": "2026-02-15T14:00:00+03:00",
      "paymentType": "POSTPAID",
      "items": [
        {
          "offerId": "BAND5-BLACK",
          "count": 1,
          "prices": {
            "payment": {"value": 3499.00, "currencyId": "RUR"}
          }
        }
      ]
    }
  ],
  "paging": {
    "nextPageToken": "eyJuZXh0SWQiOjc3MDAxMTI1fQ=="
  }
}
MOCK_EOF
        return 0
    fi

    local body
    if [[ -n "$status" ]]; then
        body=$(jq -n --argjson limit "$limit" --arg s "$status" '{limit:$limit,statuses:[$s]}')
    else
        body=$(jq -n --argjson limit "$limit" '{limit:$limit}')
    fi

    ymarket_request "POST" "/v1/businesses/{businessId}/orders" "$body" "business"
}

ym_get_order() {
    local order_id=$1; shift
    local mock_mode=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --mock) mock_mode=true; shift ;;
            *) shift ;;
        esac
    done

    [[ -z "$order_id" ]] && echo "ERROR: ID заказа обязателен" >&2 && return 1

    if [[ "$mock_mode" == "true" ]]; then
        cat <<EOF
{
  "order": {
    "orderId": $order_id,
    "campaignId": 21098765,
    "programType": "FBS",
    "status": "PROCESSING",
    "substatus": "STARTED",
    "creationDate": "2026-02-16T08:30:00+03:00",
    "items": [
      {
        "offerId": "TWS-PRO-001",
        "count": 2,
        "prices": {
          "payment": {"value": 1999.00, "currencyId": "RUR"}
        }
      }
    ]
  }
}
EOF
        return 0
    fi

    ymarket_request "GET" "/v2/campaigns/{campaignId}/orders/${order_id}" "{}" "campaign"
}

ym_get_orders_stats() {
    local mock_mode=false
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mock) mock_mode=true; shift ;;
            *) shift ;;
        esac
    done

    local orders_json=$(ym_get_orders ${mock_mode:+--mock})
    [[ -z "$orders_json" ]] && echo "ERROR: Нет данных" >&2 && return 1

    local total=$(echo "$orders_json" | jq -r '.orders | length')
    local processing=$(echo "$orders_json" | jq -r '[.orders[] | select(.status == "PROCESSING")] | length')
    local delivery=$(echo "$orders_json" | jq -r '[.orders[] | select(.status == "DELIVERY")] | length')

    cat <<EOF
{
  "total": $total,
  "by_status": {
    "PROCESSING": $processing,
    "DELIVERY": $delivery
  }
}
EOF
}
