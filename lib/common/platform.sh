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

# Получить человеческое имя платформы
platform_display_name() {
    case "${1:-$CURRENT_PLATFORM}" in
        ozon)    echo "Ozon" ;;
        wb)      echo "Wildberries" ;;
        ymarket) echo "Яндекс Маркет" ;;
        *)       echo "$1" ;;
    esac
}
