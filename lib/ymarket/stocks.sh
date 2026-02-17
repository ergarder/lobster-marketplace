#!/bin/bash
# Yandex Market остатки
# Особенности: campaignId, items array max 1 element, exact SKU matching, max 2000 SKUs

ym_get_stocks() {
    local mock_mode=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --mock) mock_mode=true; shift ;;
            *) shift ;;
        esac
    done

    if [[ "$mock_mode" == "true" ]]; then
        cat <<'MOCK_EOF'
{
  "status": "OK",
  "warehouses": [
    {
      "warehouseId": 300100,
      "offers": [
        {
          "offerId": "TWS-PRO-001",
          "stocks": [{"count": 45, "updatedAt": "2026-02-16T10:00:00+03:00"}]
        },
        {
          "offerId": "HOME-MINI-BLK",
          "stocks": [{"count": 8, "updatedAt": "2026-02-16T09:00:00+03:00"}]
        },
        {
          "offerId": "BAND5-BLACK",
          "stocks": [{"count": 3, "updatedAt": "2026-02-15T14:00:00+03:00"}]
        },
        {
          "offerId": "MOUSE-WIRELESS",
          "stocks": [{"count": 120, "updatedAt": "2026-02-16T08:00:00+03:00"}]
        },
        {
          "offerId": "KEYBOARD-MINI",
          "stocks": [{"count": 0, "updatedAt": "2026-02-14T12:00:00+03:00"}]
        }
      ]
    }
  ]
}
MOCK_EOF
        return 0
    fi

    ymarket_request "POST" "/v2/campaigns/{campaignId}/offers/stocks" "{}" "campaign"
}

ym_update_stocks() {
    local sku=$1
    local new_quantity=$2
    local mock_mode=false
    local batch_id="${BATCH_ID:-}"

    shift 2
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mock) mock_mode=true; shift ;;
            --batch-id) batch_id="$2"; shift 2 ;;
            --warehouse) shift 2 ;;
            --audit-old-stock) shift 2 ;;
            *) shift ;;
        esac
    done

    [[ -z "$sku" ]] || [[ -z "$new_quantity" ]] && echo "ERROR: SKU и количество обязательны" >&2 && return 1

    if [[ -n "$batch_id" ]] && type audit_log_change &>/dev/null; then
        audit_log_change "stock_update" "$sku" "unknown" "$new_quantity" "$batch_id" "pending"
    fi

    if [[ "$mock_mode" == "true" ]]; then
        [[ -n "$batch_id" ]] && type audit_update_status &>/dev/null && audit_update_status "$batch_id" "$sku" "success"
        cat <<EOF
{"status": "OK", "result": [{"offer_id": "$sku", "updated": true, "errors": []}]}
EOF
        return 0
    fi

    # Note: items array must have exactly 1 element
    local updated_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    local data=$(cat <<EOF
{
  "skus": [
    {
      "sku": "$sku",
      "items": [
        {
          "count": $new_quantity,
          "updatedAt": "$updated_at"
        }
      ]
    }
  ]
}
EOF
)

    local response
    response=$(ymarket_request "PUT" "/v2/campaigns/{campaignId}/offers/stocks" "$data" "campaign")
    local result=$?

    if [[ -n "$batch_id" ]] && type audit_update_status &>/dev/null; then
        [[ $result -eq 0 ]] && audit_update_status "$batch_id" "$sku" "success" || audit_update_status "$batch_id" "$sku" "fail"
    fi

    echo "$response"
    return $result
}

ym_get_stock_by_sku() {
    local sku=$1; shift
    local args=()
    while [[ $# -gt 0 ]]; do
        args+=("$1"); shift
    done

    local stocks_json=$(ym_get_stocks "${args[@]}")
    echo "$stocks_json" | jq --arg sku "$sku" '.warehouses[].offers[] | select(.offerId == $sku)' 2>/dev/null
}
