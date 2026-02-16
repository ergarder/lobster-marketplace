#!/bin/bash
# Structured audit log для marketplace операций
# Формат: TIMESTAMP|USER|BATCH_ID|ACTION|SKU|OLD_VALUE|NEW_VALUE|STATUS

# Директория и файл audit лога
AUDIT_DIR="${HOME}/.openclaw/marketplace"
AUDIT_LOG="${AUDIT_DIR}/audit.log"
AUDIT_LOCK="${AUDIT_DIR}/audit.lock"

# Инициализировать audit систему
# Создаёт директории, ротирует логи старше 90 дней
audit_init() {
    mkdir -p "$AUDIT_DIR"
    
    # Ротация: удалить записи старше 90 дней
    if [[ -f "$AUDIT_LOG" ]]; then
        local cutoff_date=$(date -d '90 days ago' '+%Y-%m-%d' 2>/dev/null || date -v-90d '+%Y-%m-%d' 2>/dev/null)
        if [[ -n "$cutoff_date" ]]; then
            local tmp_file="${AUDIT_LOG}.tmp"
            awk -F'|' -v cutoff="$cutoff_date" '{
                split($1, dt, " ");
                if (dt[1] >= cutoff) print
            }' "$AUDIT_LOG" > "$tmp_file" 2>/dev/null && mv "$tmp_file" "$AUDIT_LOG"
        fi
    fi
}

# Сгенерировать уникальный batch ID
# Format: YYYYMMDD-HHMMSS-RANDOM
audit_generate_batch_id() {
    echo "$(date '+%Y%m%d-%H%M%S')-$(head -c 4 /dev/urandom | od -An -tx4 | tr -d ' ')"
}

# Маскировать чувствительные данные (API ключи)
_audit_mask_sensitive() {
    local text="$1"
    echo "$text" | sed -E \
        -e 's/(Api-Key|API_KEY|OZON_API_KEY)[=: ]*[^ |]+/\1=***MASKED***/g' \
        -e 's/(Client-Id|CLIENT_ID|OZON_CLIENT_ID)[=: ]*[0-9]+/\1=***MASKED***/g'
}

# Записать одно изменение в audit log
# Args:
#   $1 - ACTION (price_update, stock_update, rollback_price, rollback_stock)
#   $2 - SKU
#   $3 - OLD_VALUE
#   $4 - NEW_VALUE
#   $5 - BATCH_ID
#   $6 - STATUS (pending, success, fail) — по умолчанию "pending"
audit_log_change() {
    local action="$1"
    local sku="$2"
    local old_value="$3"
    local new_value="$4"
    local batch_id="${5:-NOBATCH}"
    local status="${6:-pending}"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local user="${USER:-$(whoami)}"
    
    # Маскировать sensitive данные
    old_value=$(_audit_mask_sensitive "$old_value")
    new_value=$(_audit_mask_sensitive "$new_value")
    
    local entry="${timestamp}|${user}|${batch_id}|${action}|${sku}|${old_value}|${new_value}|${status}"
    
    # Atomic write с flock
    (
        flock -x 200
        echo "$entry" >> "$AUDIT_LOG"
    ) 200>"$AUDIT_LOCK"
}

# Обновить статус последней записи для SKU+BATCH_ID
# Args:
#   $1 - BATCH_ID
#   $2 - SKU
#   $3 - новый STATUS (success, fail)
audit_update_status() {
    local batch_id="$1"
    local sku="$2"
    local new_status="$3"
    
    if [[ ! -f "$AUDIT_LOG" ]]; then
        return 1
    fi
    
    (
        flock -x 200
        local tmp_file="${AUDIT_LOG}.tmp"
        local updated=false
        # Обновить ПОСЛЕДНЮЮ запись с данным batch_id + sku + status=pending
        # Читаем файл в обратном порядке, обновляем первую найденную, потом обратно
        tac "$AUDIT_LOG" | awk -F'|' -v bid="$batch_id" -v s="$sku" -v ns="$new_status" -v done=0 '{
            if (done == 0 && $3 == bid && $5 == s && $8 == "pending") {
                $8 = ns;
                done = 1;
            }
            print $1"|"$2"|"$3"|"$4"|"$5"|"$6"|"$7"|"$8
        }' | tac > "$tmp_file"
        mv "$tmp_file" "$AUDIT_LOG"
    ) 200>"$AUDIT_LOCK"
}

# Получить все записи batch по ID
# Args: $1 - BATCH_ID
audit_get_batch() {
    local batch_id="$1"
    
    if [[ ! -f "$AUDIT_LOG" ]]; then
        return 1
    fi
    
    grep "|${batch_id}|" "$AUDIT_LOG" 2>/dev/null
}

# Получить историю изменений SKU
# Args:
#   $1 - SKU
#   $2 - количество последних записей (опционально, по умолчанию все)
audit_get_by_sku() {
    local sku="$1"
    local limit="${2:-0}"
    
    if [[ ! -f "$AUDIT_LOG" ]]; then
        return 1
    fi
    
    local results=$(awk -F'|' -v s="$sku" '$5 == s' "$AUDIT_LOG" 2>/dev/null)
    
    if [[ "$limit" -gt 0 ]]; then
        echo "$results" | tail -n "$limit"
    else
        echo "$results"
    fi
}

# Получить последний batch_id текущего пользователя
# Args:
#   $1 - ACTION фильтр (опционально, например "price_update")
audit_get_last_batch_id() {
    local action_filter="${1:-}"
    local user="${USER:-$(whoami)}"
    
    if [[ ! -f "$AUDIT_LOG" ]]; then
        return 1
    fi
    
    if [[ -n "$action_filter" ]]; then
        grep "|${user}|" "$AUDIT_LOG" | grep "|${action_filter}|" | tail -1 | cut -d'|' -f3
    else
        grep "|${user}|" "$AUDIT_LOG" | tail -1 | cut -d'|' -f3
    fi
}

# Rollback batch операции
# Args:
#   $1 - BATCH_ID
#   $2 - тип ("price" или "stock")
#   $3 - mock_mode (true/false)
#   $4 - force_confirm (true = пропустить подтверждение; для rollback всегда false)
rollback_batch() {
    local batch_id="$1"
    local type="$2"
    local mock_mode="${3:-false}"
    local force_confirm="${4:-false}"
    
    if [[ -z "$batch_id" ]]; then
        echo "ERROR: BATCH_ID обязателен" >&2
        return 1
    fi
    
    # Получить записи batch
    local batch_records=$(audit_get_batch "$batch_id")
    
    if [[ -z "$batch_records" ]]; then
        echo "ERROR: Batch $batch_id не найден в audit log" >&2
        return 1
    fi
    
    # Фильтровать по типу если указан
    if [[ -n "$type" ]]; then
        batch_records=$(echo "$batch_records" | grep "|${type}_update|")
        if [[ -z "$batch_records" ]]; then
            echo "ERROR: Нет записей типа ${type}_update в batch $batch_id" >&2
            return 1
        fi
    fi
    
    # Проверить что все записи имеют статус success
    local failed_records=$(echo "$batch_records" | awk -F'|' '$8 != "success"')
    if [[ -n "$failed_records" ]]; then
        echo "ERROR: Не все записи в batch имеют статус success:" >&2
        echo "$failed_records" | awk -F'|' '{printf "  SKU: %s, Status: %s\n", $5, $8}' >&2
        echo "Невозможно откатить batch с ошибками" >&2
        return 1
    fi
    
    # Проверить что это не rollback-записи (нельзя откатить откат)
    local rollback_records=$(echo "$batch_records" | grep "|rollback_")
    if [[ -n "$rollback_records" ]]; then
        echo "ERROR: Batch $batch_id — это уже rollback. Нельзя откатить откат." >&2
        return 1
    fi
    
    # Показать preview
    local record_count=$(echo "$batch_records" | wc -l)
    echo ""
    echo "🔄 Rollback batch: $batch_id"
    echo "   Записей для отката: $record_count"
    echo ""
    echo "   Будут выполнены следующие откаты:"
    echo "$batch_records" | awk -F'|' '{printf "   SKU: %-20s  %s → %s (было: %s → %s)\n", $5, $7, $6, $6, $7}'
    echo ""
    
    # Запросить подтверждение (ВСЕГДА, --yes не работает для rollback)
    if [[ "$force_confirm" != "true" ]]; then
        read -p "⚠️  Подтвердите rollback (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Rollback отменён"
            return 0
        fi
    fi
    
    # Создать новый batch для rollback операций
    local rollback_batch_id=$(audit_generate_batch_id)
    local success_count=0
    local fail_count=0
    
    echo ""
    echo "🔄 Выполняется rollback..."
    
    while IFS='|' read -r timestamp user bid action sku old_value new_value status; do
        local rollback_action="rollback_${action%%_*}"
        
        # Логируем начало отката
        audit_log_change "$rollback_action" "$sku" "$new_value" "$old_value" "$rollback_batch_id" "pending"
        
        # Выполняем обратную операцию
        local result=0
        if [[ "$action" == "price_update" ]]; then
            local update_args=("$sku" "$old_value")
            [[ "$mock_mode" == "true" ]] && update_args+=("--mock")
            update_price "${update_args[@]}" > /dev/null 2>&1
            result=$?
        elif [[ "$action" == "stock_update" ]]; then
            local update_args=("$sku" "$old_value")
            [[ "$mock_mode" == "true" ]] && update_args+=("--mock")
            update_stock "${update_args[@]}" > /dev/null 2>&1
            result=$?
        fi
        
        if [[ $result -eq 0 ]]; then
            audit_update_status "$rollback_batch_id" "$sku" "success"
            ((success_count++))
            echo "   ✅ $sku: $new_value → $old_value"
        else
            audit_update_status "$rollback_batch_id" "$sku" "fail"
            ((fail_count++))
            echo "   ❌ $sku: ошибка отката"
            
            # При ошибке — остановить и предложить продолжить
            echo ""
            echo "ERROR: Ошибка при откате SKU $sku" >&2
            echo "Обработано: $success_count успешно, $fail_count с ошибкой" >&2
            echo "Rollback batch ID: $rollback_batch_id" >&2
            return 1
        fi
    done <<< "$batch_records"
    
    echo ""
    echo "✅ Rollback завершён: $success_count позиций откачено"
    echo "   Rollback batch ID: $rollback_batch_id"
    
    return 0
}

# Показать историю изменений
# Args:
#   --sku <sku> - фильтр по SKU
#   --last <N> - последние N записей
#   --batch <id> - фильтр по batch ID
audit_show_history() {
    local sku=""
    local last_n=20
    local batch_id=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --sku)
                sku="$2"
                shift 2
                ;;
            --last)
                last_n="$2"
                shift 2
                ;;
            --batch)
                batch_id="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
    
    if [[ ! -f "$AUDIT_LOG" ]]; then
        echo "Audit log пуст"
        return 0
    fi
    
    local records=""
    
    if [[ -n "$batch_id" ]]; then
        records=$(audit_get_batch "$batch_id")
    elif [[ -n "$sku" ]]; then
        records=$(audit_get_by_sku "$sku" "$last_n")
    else
        records=$(tail -n "$last_n" "$AUDIT_LOG")
    fi
    
    if [[ -z "$records" ]]; then
        echo "Нет записей"
        return 0
    fi
    
    # Форматированный вывод
    printf "%-19s %-8s %-25s %-15s %-20s %-10s → %-10s %s\n" \
        "TIMESTAMP" "USER" "BATCH_ID" "ACTION" "SKU" "OLD" "NEW" "STATUS"
    echo "$(printf '%.0s-' {1..120})"
    
    echo "$records" | while IFS='|' read -r timestamp user batch_id action sku old_val new_val status; do
        printf "%-19s %-8s %-25s %-15s %-20s %-10s → %-10s %s\n" \
            "$timestamp" "$user" "$batch_id" "$action" "$sku" "$old_val" "$new_val" "$status"
    done
}

# Инициализация при загрузке модуля
audit_init
