#!/bin/bash
# Система логирования

# Директория для логов
LOG_DIR="${HOME}/.openclaw/marketplace/logs"
LOG_FILE="${LOG_DIR}/marketplace-$(date +%Y-%m-%d).log"

# Уровни логирования
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARN=2
LOG_LEVEL_ERROR=3

# Текущий уровень логирования (по умолчанию INFO)
CURRENT_LOG_LEVEL=${CURRENT_LOG_LEVEL:-$LOG_LEVEL_INFO}

# Инициализация логирования
init_logger() {
    mkdir -p "$LOG_DIR"
    
    # Ротация старых логов (удалить логи старше 30 дней)
    find "$LOG_DIR" -name "marketplace-*.log" -mtime +30 -delete 2>/dev/null
}

# Записать сообщение в лог
# Args:
#   $1 - уровень (DEBUG, INFO, WARN, ERROR)
#   $2 - сообщение
#   $3 - дополнительные данные (опционально)
log_message() {
    local level=$1
    local message=$2
    local data=${3:-""}
    
    local level_num=0
    case $level in
        DEBUG) level_num=$LOG_LEVEL_DEBUG ;;
        INFO)  level_num=$LOG_LEVEL_INFO ;;
        WARN)  level_num=$LOG_LEVEL_WARN ;;
        ERROR) level_num=$LOG_LEVEL_ERROR ;;
    esac
    
    # Пропустить если уровень ниже текущего
    if [[ $level_num -lt $CURRENT_LOG_LEVEL ]]; then
        return 0
    fi
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp] [$level] $message"
    
    if [[ -n "$data" ]]; then
        log_entry="$log_entry | $data"
    fi
    
    # Маскировать чувствительные данные
    log_entry=$(echo "$log_entry" | sed -E 's/(Api-Key|API_KEY|OZON_API_KEY): [^ ]+/\1: ***MASKED***/g')
    log_entry=$(echo "$log_entry" | sed -E 's/(Client-Id|CLIENT_ID|OZON_CLIENT_ID): [0-9]+/\1: ***MASKED***/g')
    
    echo "$log_entry" >> "$LOG_FILE"
}

# Алиасы для разных уровней
log_debug() {
    log_message "DEBUG" "$1" "${2:-}"
}

log_info() {
    log_message "INFO" "$1" "${2:-}"
}

log_warn() {
    log_message "WARN" "$1" "${2:-}"
}

log_error() {
    log_message "ERROR" "$1" "${2:-}"
}

# Логировать API запрос
# Args:
#   $1 - метод (GET, POST, PUT)
#   $2 - endpoint
#   $3 - HTTP статус
#   $4 - время выполнения (опционально)
log_api_request() {
    local method=$1
    local endpoint=$2
    local status=$3
    local duration=${4:-"N/A"}
    
    log_info "API Request: $method $endpoint" "status=$status duration=${duration}ms"
}

# Логировать ошибку API
# Args:
#   $1 - endpoint
#   $2 - HTTP статус
#   $3 - сообщение об ошибке
log_api_error() {
    local endpoint=$1
    local status=$2
    local error=$3
    
    log_error "API Error: $endpoint" "status=$status error=\"$error\""
}

# Показать последние записи из лога
# Args: $1 - количество строк (по умолчанию 50)
show_logs() {
    local lines=${1:-50}
    
    if [[ ! -f "$LOG_FILE" ]]; then
        echo "Лог файл не найден: $LOG_FILE"
        return 1
    fi
    
    tail -n "$lines" "$LOG_FILE"
}

# Очистить все логи
clear_logs() {
    rm -f "${LOG_DIR}"/marketplace-*.log
    log_info "Logs cleared"
    echo "Все логи удалены"
}

# Инициализация при загрузке модуля
init_logger
