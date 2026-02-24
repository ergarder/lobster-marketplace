#!/bin/bash
# Платформа: определение, валидация, загрузка модулей

SUPPORTED_PLATFORMS=(ozon wb ymarket)
CURRENT_PLATFORM="${CURRENT_PLATFORM:-ozon}"

# Определить платформу из аргументов
# Извлекает --platform <name> из массива аргументов, удаляя его
# Sets: CURRENT_PLATFORM, REMAINING_ARGS
resolve_platform() {
    REMAINING_ARGS=()
    while [[ $# -gt 0 ]]; do
        case $1 in
            --platform)
                CURRENT_PLATFORM="$2"
                shift 2
                ;;
            *)
                REMAINING_ARGS+=("$1")
                shift
                ;;
        esac
    done

    validate_platform "$CURRENT_PLATFORM" || return 1
}

# Проверить что платформа поддерживается
validate_platform() {
    local platform="${1:-$CURRENT_PLATFORM}"
    for p in "${SUPPORTED_PLATFORMS[@]}"; do
        [[ "$p" == "$platform" ]] && return 0
    done
    echo "ERROR: Неизвестная платформа: $platform" >&2
    echo "Поддерживаемые: ${SUPPORTED_PLATFORMS[*]}" >&2
    return 1
}

# Загрузить модули платформы
# Args: $1 - platform, $2.. - modules (auth, orders, prices, stocks, http)
source_platform_libs() {
    local platform="${1:-$CURRENT_PLATFORM}"
    shift
    local modules=("$@")

    local lib_dir
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    # Always load common modules
    [[ -z "${_COMMON_LOGGER_LOADED:-}" ]] && source "${lib_dir}/common/logger.sh" && _COMMON_LOGGER_LOADED=1
    [[ -z "${_COMMON_FORMATTER_LOADED:-}" ]] && source "${lib_dir}/common/formatter.sh" && _COMMON_FORMATTER_LOADED=1
    [[ -z "${_COMMON_AUDIT_LOADED:-}" ]] && source "${lib_dir}/common/audit.sh" && _COMMON_AUDIT_LOADED=1

    # Load common http (mock_request, batch_execute, platform_request)
    [[ -z "${_COMMON_HTTP_LOADED:-}" ]] && source "${lib_dir}/common/http.sh" && _COMMON_HTTP_LOADED=1

    # Load platform-specific http
    if [[ -f "${lib_dir}/${platform}/http.sh" ]]; then
        source "${lib_dir}/${platform}/http.sh"
    fi

    # Load platform auth
    source "${lib_dir}/${platform}/auth.sh"

    # Load requested modules
    for mod in "${modules[@]}"; do
        local mod_file="${lib_dir}/${platform}/${mod}.sh"
        if [[ -f "$mod_file" ]]; then
            source "$mod_file"
        else
            log_warn "Module not found: ${platform}/${mod}.sh"
        fi
    done
}

# Проверить что значение является положительным целым числом
# Args: $1 - value, $2 - parameter name (for error message)
validate_positive_int() {
    local val="$1"
    local name="${2:-parameter}"
    if ! [[ "$val" =~ ^[0-9]+$ ]] || [[ "$val" == "0" ]]; then
        echo "ERROR: $name должен быть положительным числом, получено: $val" >&2
        return 1
    fi
    return 0
}

# Безопасная загрузка credentials: проверяем что файл содержит только KEY=value и комментарии
# Args: $1 - путь к файлу
safe_source_credentials() {
    local cred_file="$1"
    if [[ ! -f "$cred_file" ]]; then
        return 1
    fi
    # Reject files containing shell metacharacters or commands
    # Allow only: empty lines, comments (#...), KEY=value (no semicolons, backticks, $() etc.)
    local bad_lines
    bad_lines=$(grep -nvE '^[[:space:]]*(#.*)?$|^[A-Za-z_][A-Za-z0-9_]*=[^;`$()&|<>]*$' "$cred_file" 2>/dev/null)
    if [[ -n "$bad_lines" ]]; then
        echo "ERROR: Credentials файл содержит небезопасные строки:" >&2
        echo "$bad_lines" >&2
        echo "Допустимый формат: KEY=value (без спецсимволов shell)" >&2
        return 1
    fi
    source "$cred_file"
}

# Загрузить и проверить credentials текущей платформы
# Returns: 0 если успешно, 1 если ошибка (с сообщением)
load_and_check_credentials() {
    case "${CURRENT_PLATFORM:-ozon}" in
        ozon)    load_credentials && check_ozon_credentials ;;
        wb)      load_wb_credentials && check_wb_credentials ;;
        ymarket) load_ym_credentials && check_ym_credentials ;;
        *)       echo "ERROR: Unknown platform: $CURRENT_PLATFORM" >&2; return 1 ;;
    esac
}

# Получить человеческое имя платформы
platform_display_name() {
    case "${1:-$CURRENT_PLATFORM}" in
        ozon)    echo "Ozon" ;;
        wb)      echo "Wildberries" ;;
        ymarket) echo "Яндекс Маркет" ;;
        *)       echo "$1" ;;
    esac
}
