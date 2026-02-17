#!/bin/bash
# WB остатки
# Особенности: stocks per-warehouse, warehouseId in path

WB_WAREHOUSE_CACHE="${HOME}/.openclaw/marketplace/wb-warehouses.json"

wb_get_warehouses() {
    local mock_mode=false
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mock) mock_mode=true; shift ;;
            *) shift ;;
        esac
    done

    if [[ "$mock_mode" == "true" ]]; then
        cat <<'MOCK_EOF'
[
  {"id": 507921, "name": "Склад Москва (Коледино)", "officeId": 15},
  {"id": 507922, "name": "Склад СПб (Шушары)", "officeId": 16}
]
MOCK_EOF
        return 0
    fi

    local response=$(wb_request "GET" "/api/v3/warehouses" "{}" "marketplace")
    local result=$?

    if [[ $result -eq 0 ]] && [[ -n "$response" ]]; then
        # Cache warehouses
        mkdir -p "$(dirname "$WB_WAREHOUSE_CACHE")"
        echo "$response" > "$WB_WAREHOUSE_CACHE"
    fi

    echo "$response"
    return $result
}

_wb_resolve_warehouse() {
    local warehouse_id="$1"
    local mock_mode="$2"

    if [[ -n "$warehouse_id" ]]; then
        echo "$warehouse_id"
        return 0
    fi

    # Try cache
    if [[ -f "$WB_WAREHOUSE_CACHE" ]]; then
        local first=$(jq -r '.[0].id // empty' "$WB_WAREHOUSE_CACHE" 2>/dev/null)
        if [[ -n "$first" ]]; then
            echo "$first"
            return 0
        fi
    fi

    # Fetch
    local wh_json
    if [[ "$mock_mode" == "true" ]]; then
        wh_json=$(wb_get_warehouses --mock)
    else
        wh_json=$(wb_get_warehouses)
    fi

    local first=$(echo "$wh_json" | jq -r '.[0].id // empty' 2>/dev/null)
    if [[ -n "$first" ]]; then
        echo "$first"
        return 0
    fi

    echo "ERROR: Не удалось определить склад WB. Укажите --warehouse" >&2
    return 1
}

wb_get_stocks() {
    local mock_mode=false
    local warehouse_id=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --mock) mock_mode=true; shift ;;
            --warehouse) warehouse_id="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [[ "$mock_mode" == "true" ]]; then
        cat <<'MOCK_EOF'
{
  "stocks": [
    {"sku": "2000000000011", "amount": 45, "nmId": 12345678},
    {"sku": "2000000000028", "amount": 8, "nmId": 87654321},
    {"sku": "2000000000035", "amount": 3, "nmId": 11223344},
    {"sku": "2000000000042", "amount": 120, "nmId": 55667788},
    {"sku": "2000000000059", "amount": 0, "nmId": 99001122}
  ]
}
MOCK_EOF
        return 0
    fi

    local wh_id=$(_wb_resolve_warehouse "$warehouse_id" "$mock_mode")
    [[ $? -ne 0 ]] && return 1

    wb_request "POST" "/api/v3/stocks/${wh_id}" '{"skus":["*"]}' "marketplace"
}

wb_update_stocks() {
    local sku=$1
    local new_quantity=$2
    local mock_mode=false
    local warehouse_id=""
    local batch_id="${BATCH_ID:-}"

    shift 2
    while [[ $# -gt 0 ]]; do
        case $1 in
            --mock) mock_mode=true; shift ;;
            --warehouse) warehouse_id="$2"; shift 2 ;;
            --batch-id) batch_id="$2"; shift 2 ;;
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
{"result": [{"offer_id": "$sku", "updated": true, "errors": []}]}
EOF
        return 0
    fi

    local wh_id=$(_wb_resolve_warehouse "$warehouse_id" "$mock_mode")
    [[ $? -ne 0 ]] && return 1

    local data="{\"stocks\":[{\"sku\":\"$sku\",\"amount\":$new_quantity}]}"
    local response
    response=$(wb_request "PUT" "/api/v3/stocks/${wh_id}" "$data" "marketplace")
    local result=$?

    if [[ -n "$batch_id" ]] && type audit_update_status &>/dev/null; then
        [[ $result -eq 0 ]] && audit_update_status "$batch_id" "$sku" "success" || audit_update_status "$batch_id" "$sku" "fail"
    fi

    echo "$response"
    return $result
}

wb_get_stock_by_sku() {
    local sku=$1; shift
    local args=()
    while [[ $# -gt 0 ]]; do
        args+=("$1"); shift
    done

    local stocks_json=$(wb_get_stocks "${args[@]}")
    echo "$stocks_json" | jq --arg sku "$sku" '.stocks[] | select(.sku == $sku)' 2>/dev/null
}
