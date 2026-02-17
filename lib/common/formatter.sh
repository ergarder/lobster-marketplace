#!/bin/bash
# Форматирование JSON данных в human-readable формат для агента

# === Общие утилиты для мульти-платформы ===

# Конвертировать копейки в рубли
# Args: $1 - сумма в копейках (целое число)
kopecks_to_rubles() {
    local kopecks="${1:-0}"
    awk -v k="$kopecks" 'BEGIN {printf "%.2f", k / 100}'
}

# Конвертировать рубли в копейки
# Args: $1 - сумма в рублях (десятичное число)
rubles_to_kopecks() {
    local rubles="${1:-0}"
    awk -v r="$rubles" 'BEGIN {printf "%d", r * 100}'
}

# Конвертировать ISO 4217 numeric → string
# Args: $1 - числовой код (643, 933, ...)
numeric_currency_to_iso() {
    case "${1:-}" in
        643) echo "RUB" ;;
        933) echo "BYN" ;;
        840) echo "USD" ;;
        978) echo "EUR" ;;
        398) echo "KZT" ;;
        *)   echo "$1" ;;
    esac
}

# Нормализовать код валюты (RUR → RUB)
normalize_currency() {
    case "${1:-}" in
        RUR) echo "RUB" ;;
        *)   echo "$1" ;;
    esac
}

# Конвертировать Unix timestamp → human date
# Args: $1 - unix timestamp (seconds)
format_unix_timestamp() {
    local ts="$1"
    if date --version >/dev/null 2>&1; then
        date -d "@$ts" '+%d.%m.%Y %H:%M' 2>/dev/null || echo "$ts"
    else
        date -r "$ts" '+%d.%m.%Y %H:%M' 2>/dev/null || echo "$ts"
    fi
}

# === Форматтеры WB ===

format_wb_orders() {
    local json=$1
    local count=$(echo "$json" | jq -r '.orders | length' 2>/dev/null)

    if [[ -z "$count" ]] || [[ "$count" == "0" ]] || [[ "$count" == "null" ]]; then
        echo "Нет новых заказов"
        return 0
    fi

    echo "📦 Найдено заказов: $count"
    echo ""

    echo "$json" | jq -r '
        .orders[] |
        "Заказ №\(.id)\n" +
        "📊 Статус продавца: \(.supplierStatus)\n" +
        "📊 Статус WB: \(.wbStatus)\n" +
        "💰 Цена: \(.salePrice / 100) ₽\n" +
        "📅 Создан: \(.createdAt)\n" +
        "---"
    '
}

format_wb_order_status() {
    local json=$1
    echo "$json" | jq -r '.orders[] |
"Заказ №\(.id)
📊 Статус продавца: \(.supplierStatus)
📊 Статус WB: \(.wbStatus)
💰 Цена: \(.salePrice / 100) ₽
🏷️ Артикул: \(.article)
---"'
}

format_wb_price() {
    local json=$1
    echo "$json" | jq -r '.data.listGoods[0] //
    {nmID: "N/A", sizes: [{price: 0}]} |
"Артикул: \(.nmID)
💰 Цена: \(.sizes[0].price / 100) ₽"'
}

format_wb_stocks() {
    local json=$1
    local count=$(echo "$json" | jq -r '.stocks | length' 2>/dev/null)

    if [[ -z "$count" ]] || [[ "$count" == "0" ]] || [[ "$count" == "null" ]]; then
        echo "Нет данных об остатках"
        return 0
    fi

    echo "📊 Остатки (позиций: $count):"
    echo ""

    echo "$json" | jq -r '.stocks[] |
"SKU: \(.sku)
📦 Остаток: \(.amount) шт
---"'
}

# === Форматтеры Yandex Market ===

format_ym_orders() {
    local json=$1
    local count=$(echo "$json" | jq -r '.orders | length' 2>/dev/null)

    if [[ -z "$count" ]] || [[ "$count" == "0" ]] || [[ "$count" == "null" ]]; then
        echo "Нет новых заказов"
        return 0
    fi

    echo "📦 Найдено заказов: $count"
    echo ""

    echo "$json" | jq -r '
        .orders[] |
        "Заказ №\(.orderId)\n" +
        "📊 Статус: \(.status)" +
        (if .substatus then " (\(.substatus))" else "" end) + "\n" +
        "🏪 Модель: \(.programType // "N/A")\n" +
        "📅 Создан: \(.creationDate)\n" +
        "---"
    '
}

format_ym_order_status() {
    local json=$1
    echo "$json" | jq -r '.order |
"Заказ №\(.orderId)
📊 Статус: \(.status)" +
(if .substatus then " (\(.substatus))" else "" end) + "
🏪 Модель: \(.programType // "N/A")
📅 Создан: \(.creationDate)
💰 Товары:" +
(.items[] | "
  • \(.offerId)
    Кол-во: \(.count) шт
    Цена: \(.prices.payment.value) ₽")'
}

format_ym_price() {
    local json=$1
    echo "$json" | jq -r '.result.offers[0] // {offerId:"N/A"} |
"SKU: \(.offerId)
💰 Цена: \(.price.value // "N/A") ₽
Валюта: \(.price.currencyId // "N/A")"'
}

format_ym_stocks() {
    local json=$1
    local count=$(echo "$json" | jq -r '.warehouses[0].offers | length' 2>/dev/null)

    if [[ -z "$count" ]] || [[ "$count" == "0" ]] || [[ "$count" == "null" ]]; then
        echo "Нет данных об остатках"
        return 0
    fi

    echo "📊 Остатки (позиций: $count):"
    echo ""

    echo "$json" | jq -r '.warehouses[].offers[] |
"SKU: \(.offerId)
📦 Остаток: \(.stocks[0].count // 0) шт
Обновлено: \(.stocks[0].updatedAt // "N/A")
---"'
}

# Форматировать список заказов
# Input: JSON с заказами из Ozon API
format_orders() {
    local json=$1
    
    # Проверка на пустой результат
    local count=$(echo "$json" | jq -r '.result.postings | length' 2>/dev/null)
    
    if [[ -z "$count" ]] || [[ "$count" == "0" ]] || [[ "$count" == "null" ]]; then
        echo "Нет новых заказов"
        return 0
    fi
    
    echo "📦 Найдено заказов: $count"
    echo ""
    
    echo "$json" | jq -r '
        .result.postings[] | 
        "Заказ №\(.posting_number)\n" +
        "📊 Статус: \(.status)\n" +
        "📦 Товаров: \(.products | length) шт\n" +
        "💰 Сумма: \(.products | map(.price | tonumber) | add) ₽\n" +
        "⏰ Отгрузка до: \(.shipment_date)\n" +
        "---"
    '
}

# Форматировать статус заказа
# Input: JSON с деталями заказа
format_order_status() {
    local json=$1
    
    echo "$json" | jq -r '.result | 
"Заказ №\(.posting_number)
📊 Статус: \(.status)
📅 Создан: \(.in_process_at)
⏰ Отгрузка до: \(.shipment_date)
🏢 Склад: \(.warehouse_name // "не указан")

Товары:" + 
(.products[] | "
  • \(.name)
    SKU: \(.sku)
    Кол-во: \(.quantity) шт
    Цена: \(.price) ₽")'
}

# Форматировать цену товара
# Input: JSON с ценой
format_price() {
    local json=$1
    
    echo "$json" | jq -r '.result.items[0] | 
"SKU: \(.offer_id)
💰 Текущая цена: \(.price.price) ₽
🏷️  Старая цена: \(.price.old_price // "не указана") ₽
📉 Мин. цена: \(.price.min_price // "не указана") ₽
💳 Цена с картой: \(.price.premium_price // "не указана") ₽"'
}

# Форматировать список остатков
# Input: JSON с остатками
format_stocks() {
    local json=$1
    local show_low=${2:-false}
    
    local count=$(echo "$json" | jq -r '.result.rows | length' 2>/dev/null)
    
    if [[ -z "$count" ]] || [[ "$count" == "0" ]] || [[ "$count" == "null" ]]; then
        echo "Нет данных об остатках"
        return 0
    fi
    
    if [[ "$show_low" == "true" ]]; then
        echo "⚠️  Товары с низкими остатками (< 10 шт):"
    else
        echo "📊 Остатки на складах (всего позиций: $count):"
    fi
    echo ""
    
    local filter='.'
    if [[ "$show_low" == "true" ]]; then
        filter='select(.stock < 10)'
    fi
    
    echo "$json" | jq -r '.result.rows[] | '"$filter"' | 
"SKU: \(.sku)
📦 Название: \(.name // "не указано")
📊 Остаток: \(.stock) шт" +
(if .stock < 10 then "\n⚠️  НИЗКИЙ ОСТАТОК!" else "" end) + "
🏢 Склад: \(.warehouse_name // "не указан")
---"'
}

# Конвертировать ISO дату в человеческий формат
# Args: $1 - ISO дата (2026-02-17T12:00:00Z)
format_date() {
    local iso_date=$1
    
    # Проверка наличия date с поддержкой -d
    if date --version >/dev/null 2>&1; then
        # GNU date
        local timestamp=$(date -d "$iso_date" +%s 2>/dev/null)
        local now=$(date +%s)
        local diff=$((timestamp - now))
        
        if [[ $diff -lt 0 ]]; then
            echo "$(date -d "$iso_date" '+%d.%m.%Y %H:%M')"
        elif [[ $diff -lt 3600 ]]; then
            echo "через $((diff / 60)) минут"
        elif [[ $diff -lt 86400 ]]; then
            echo "через $((diff / 3600)) часов"
        elif [[ $diff -lt 172800 ]]; then
            echo "завтра в $(date -d "$iso_date" '+%H:%M')"
        else
            echo "$(date -d "$iso_date" '+%d.%m.%Y %H:%M')"
        fi
    else
        # Fallback для систем без GNU date
        echo "$iso_date" | sed 's/T/ /; s/Z$//'
    fi
}

# Форматировать число с разделителями тысяч
# Args: $1 - число
format_number() {
    local number=$1
    printf "%'d" "$number" 2>/dev/null || echo "$number"
}

# Вычислить процент изменения
# Args: $1 - старая цена, $2 - новая цена
# Test: calculate_change_percent 100 150 → "+50.00%"
# Test: calculate_change_percent 100 50  → "-50.00%"
# Test: calculate_change_percent 0 100   → "новый товар"
# Test: calculate_change_percent "" 100   → "N/A"
# Test: calculate_change_percent "abc" 100 → "N/A"
calculate_change_percent() {
    local old=$1
    local new=$2
    
    # Защита от нечисловых значений
    if [[ -z "$old" ]] || [[ -z "$new" ]]; then
        echo "N/A"
        return
    fi
    
    # Валидация: оба значения должны быть числами
    if ! awk -v a="$old" 'BEGIN {exit (a+0 == a) ? 0 : 1}' 2>/dev/null; then
        echo "N/A"
        return
    fi
    if ! awk -v a="$new" 'BEGIN {exit (a+0 == a) ? 0 : 1}' 2>/dev/null; then
        echo "N/A"
        return
    fi
    
    # Обработка old=0: новый товар
    if (( $(awk -v old="$old" 'BEGIN {print (old == 0)}') )); then
        if (( $(awk -v new="$new" 'BEGIN {print (new > 0)}') )); then
            echo "новый товар"
        elif (( $(awk -v new="$new" 'BEGIN {print (new == 0)}') )); then
            echo "0.00%"
        else
            echo "N/A"
        fi
        return
    fi
    
    # Использовать awk вместо bc
    local change=$(awk -v old="$old" -v new="$new" 'BEGIN {printf "%.2f", ((new - old) / old) * 100}' 2>/dev/null)
    
    if [[ -z "$change" ]]; then
        echo "N/A"
        return
    fi
    
    # Добавить знак + для положительных значений
    if (( $(awk -v val="$change" 'BEGIN {print (val > 0)}') )); then
        echo "+${change}%"
    else
        echo "${change}%"
    fi
}
