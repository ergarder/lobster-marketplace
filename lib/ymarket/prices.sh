#!/bin/bash
# Yandex Market цены
# Особенности: price quarantine, RUR (не RUB), businessId for all price ops

ym_get_prices() {
    local sku=""
    local mock_mode=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --mock) mock_mode=true; shift ;;
            *) [[ -z "$sku" ]] && sku="$1"; shift ;;
        esac
    done

    if [[ "$mock_mode" == "true" ]]; then
        cat <<'MOCK_EOF'
{
  "status": "OK",
  "result": {
    "offers": [
      {
        "offerId": "TWS-PRO-001",
        "price": {"value": 1999, "currencyId": "RUR"},
        "updatedAt": "2026-02-16T10:00:00+03:00"
      },
      {
        "offerId": "HOME-MINI-BLK",
        "price": {"value": 2499, "currencyId": "RUR"},
        "updatedAt": "2026-02-16T09:00:00+03:00"
      },
      {
        "offerId": "BAND5-BLACK",
        "price": {"value": 3499, "currencyId": "RUR"},
        "updatedAt": "2026-02-15T14:00:00+03:00"
      }
    ]
  }
}
MOCK_EOF
        return 0
    fi

    local body="{}"
    [[ -n "$sku" ]] && body="{\"offerIds\":[\"$sku\"]}"

    ymarket_request "POST" "/v2/businesses/{businessId}/offer-prices" "$body" "business"
}

ym_update_prices() {
    local sku=$1
    local new_price=$2
    local mock_mode=false
    local batch_id="${BATCH_ID:-}"
    local current_price_for_audit=""

    shift 2
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mock) mock_mode=true; shift ;;
            --batch-id) batch_id="$2"; shift 2 ;;
            --audit-old-price) current_price_for_audit="$2"; shift 2 ;;
            --old-price) shift 2 ;;
            *) shift ;;
        esac
    done

    [[ -z "$sku" ]] || [[ -z "$new_price" ]] && echo "ERROR: SKU и цена обязательны" >&2 && return 1

    if [[ -n "$batch_id" ]] && type audit_log_change &>/dev/null; then
        audit_log_change "price_update" "$sku" "${current_price_for_audit:-unknown}" "$new_price" "$batch_id" "pending"
    fi

    if [[ "$mock_mode" == "true" ]]; then
        [[ -n "$batch_id" ]] && type audit_update_status &>/dev/null && audit_update_status "$batch_id" "$sku" "success"
        cat <<EOF
{
  "status": "OK",
  "result": [{"offer_id": "$sku", "updated": true, "errors": []}]
}
EOF
        return 0
    fi

    # Note: YM uses RUR, not RUB
    local data=$(cat <<EOF
{
  "offers": [
    {
      "offerId": "$sku",
      "price": {
        "value": $new_price,
        "currencyId": "RUR"
      }
    }
  ]
}
EOF
)

    local response
    response=$(ymarket_request "POST" "/v2/businesses/{businessId}/offer-prices/updates" "$data" "business")
    local result=$?

    if [[ -n "$batch_id" ]] && type audit_update_status &>/dev/null; then
        [[ $result -eq 0 ]] && audit_update_status "$batch_id" "$sku" "success" || audit_update_status "$batch_id" "$sku" "fail"
    fi

    echo "$response"
    return $result
}

ym_get_quarantined_prices() {
    local sku=""
    local mock_mode=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --mock) mock_mode=true; shift ;;
            *) [[ -z "$sku" ]] && sku="$1"; shift ;;
        esac
    done

    if [[ "$mock_mode" == "true" ]]; then
        cat <<'MOCK_EOF'
{
  "status": "OK",
  "result": {
    "quarantineOffers": [
      {
        "offerId": "TWS-PRO-001",
        "currentPrice": {"value": 1999, "currencyId": "RUR"},
        "newPrice": {"value": 999, "currencyId": "RUR"},
        "verdictType": "PRICE_DROP"
      }
    ]
  }
}
MOCK_EOF
        return 0
    fi

    local body="{}"
    [[ -n "$sku" ]] && body="{\"offerIds\":[\"$sku\"]}"

    ymarket_request "POST" "/v2/businesses/{businessId}/price-quarantine" "$body" "business"
}

ym_confirm_quarantine() {
    local mock_mode=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --mock) mock_mode=true; shift ;;
            *) shift ;;
        esac
    done

    if [[ "$mock_mode" == "true" ]]; then
        echo '{"status": "OK"}'
        return 0
    fi

    # Get quarantined offers first
    local q_json=$(ym_get_quarantined_prices)
    local offer_ids=$(echo "$q_json" | jq -r '[.result.quarantineOffers[].offerId]' 2>/dev/null)

    [[ "$offer_ids" == "[]" ]] || [[ -z "$offer_ids" ]] && echo "Нет цен в карантине" && return 0

    local data="{\"offerIds\":$offer_ids}"
    ymarket_request "POST" "/v2/businesses/{businessId}/price-quarantine/confirm" "$data" "business"
}
