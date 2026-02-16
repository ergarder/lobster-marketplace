#!/bin/bash
# Форматирование JSON данных в human-readable формат для агента

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
