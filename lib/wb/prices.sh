#!/bin/bash
# WB цены
# Особенности: цены в копейках, base price + discount model

wb_get_prices() {
    local sku=""
    local mock_mode=false
    local limit=100
    local offset=0

    while [[ $# -gt 0 ]]; do
        case $1 in
            --mock) mock_mode=true; shift ;;
            --limit) limit="$2"; shift 2 ;;
            --offset) offset="$2"; shift 2 ;;
            *) [[ -z "$sku" ]]; sku="$1"; shift ;;
        esac
    done

    if [[ "$mock_mode" == "true" ]]; then
        cat <<'MOCK_EOF'
{
  "data": {
    "listGoods": [
      {
        "nmID": 12345678,
        "vendorCode": "TWS-PRO-001",
        "sizes": [
          {
            "sizeID": 0,
            "price": 199900,
            "discountedPrice": 159920,
            "techSizeName": "0"
          }
        ],
        "currencyIsoCode4217": "643",
        "discount": 20
      },
      {
        "nmID": 87654321,
        "vendorCode": "HOME-MINI-BLK",
        "sizes": [
          {
            "sizeID": 0,
            "price": 249900,
            "discountedPrice": 224910,
            "techSizeName": "0"
          }
        ],
        "currencyIsoCode4217": "643",
        "discount": 10
      },
      {
        "nmID": 11223344,
        "vendorCode": "BAND5-BLACK",
        "sizes": [
          {
            "sizeID": 0,
            "price": 349900,
            "discountedPrice": 279920,
            "techSizeName": "0"
          }
        ],
        "currencyIsoCode4217": "643",
        "discount": 20
      }
    ]
  }
}
MOCK_EOF
        return 0
    fi

    local params="limit=${limit}&offset=${offset}"
    wb_request "GET" "/api/v2/list/goods/filter?${params}" "{}" "prices"
}

wb_update_price() {
    local sku=$1
    local new_price_kopecks=$2  # kopecks!
    local mock_mode=false
    local batch_id="${BATCH_ID:-}"
    local current_price_for_audit=""

    shift 2
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mock) mock_mode=true; shift ;;
            --batch-id) batch_id="$2"; shift 2 ;;
            --audit-old-price) current_price_for_audit="$2"; shift 2 ;;
            --old-price) shift 2 ;;  # ignored for WB
            *) shift ;;
        esac
    done

    [[ -z "$sku" ]] || [[ -z "$new_price_kopecks" ]] && echo "ERROR: SKU и цена обязательны" >&2 && return 1

    # Audit
    if [[ -n "$batch_id" ]] && type audit_log_change &>/dev/null; then
        audit_log_change "price_update" "$sku" "${current_price_for_audit:-unknown}" "$(kopecks_to_rubles "$new_price_kopecks")" "$batch_id" "pending"
    fi

    if [[ "$mock_mode" == "true" ]]; then
        [[ -n "$batch_id" ]] && type audit_update_status &>/dev/null && audit_update_status "$batch_id" "$sku" "success"
        cat <<EOF
{
  "result": [{"offer_id": "$sku", "updated": true, "errors": []}]
}
EOF
        return 0
    fi

    local data=$(cat <<EOF
{
  "data": [
    {
      "nmID": $sku,
      "price": $new_price_kopecks
    }
  ]
}
EOF
)

    local response
    response=$(wb_request "POST" "/api/v2/upload/task/size" "$data" "prices")
    local result=$?

    if [[ -n "$batch_id" ]] && type audit_update_status &>/dev/null; then
        [[ $result -eq 0 ]] && audit_update_status "$batch_id" "$sku" "success" || audit_update_status "$batch_id" "$sku" "fail"
    fi

    echo "$response"
    return $result
}

wb_get_price_history() {
    local mock_mode=false
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mock) mock_mode=true; shift ;;
            *) shift ;;
        esac
    done

    if [[ "$mock_mode" == "true" ]]; then
        echo '{"data": []}'
        return 0
    fi

    wb_request "GET" "/api/v2/history/goods/size" "{}" "prices"
}
