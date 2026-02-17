#!/bin/bash
# Утренний дайджест по заказам и остаткам (мульти-платформа)
#
# Использование:
#   ./morning-digest.sh                         # только Ozon (по умолчанию)
#   ./morning-digest.sh --platform wb           # только WB
#   ./morning-digest.sh --platform all          # все настроенные платформы
#   ./morning-digest.sh --platform all --mock   # тест всех платформ

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$(cd "${SCRIPT_DIR}/../tools" && pwd)"
export PATH="${TOOLS_DIR}:${PATH}"

PLATFORM="ozon"
MOCK_FLAG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --platform) PLATFORM="$2"; shift 2 ;;
        --mock) MOCK_FLAG="--mock"; shift ;;
        *) shift ;;
    esac
done

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

get_date_ru() {
    case $(date +%m) in
        01) month="января" ;; 02) month="февраля" ;; 03) month="марта" ;;
        04) month="апреля" ;; 05) month="мая" ;; 06) month="июня" ;;
        07) month="июля" ;; 08) month="августа" ;; 09) month="сентября" ;;
        10) month="октября" ;; 11) month="ноября" ;; 12) month="декабря" ;;
    esac
    case $(date +%u) in
        1) wd="Понедельник" ;; 2) wd="Вторник" ;; 3) wd="Среда" ;;
        4) wd="Четверг" ;; 5) wd="Пятница" ;; 6) wd="Суббота" ;; 7) wd="Воскресенье" ;;
    esac
    echo "$wd, $(date +%d) $month $(date +%Y)"
}

run_digest_for_platform() {
    local plat=$1
    local plat_flag="--platform $plat"

    echo ""
    echo -e "${BLUE}━━━ $(mp-orders $plat_flag --help 2>/dev/null | head -1 || echo "$plat") ━━━${NC}"
    echo ""

    echo -e "${BLUE}📦 Заказы${NC}"
    echo "─────────────────────────────────────"
    mp-orders list $plat_flag $MOCK_FLAG 2>&1 | head -50
    echo ""

    echo -e "${BLUE}⚠️  Низкие остатки${NC}"
    echo "─────────────────────────────────────"
    mp-stocks list --low $plat_flag $MOCK_FLAG 2>&1 | head -30
    echo ""

    echo -e "${BLUE}📊 Статистика${NC}"
    echo "─────────────────────────────────────"
    mp-orders stats $plat_flag $MOCK_FLAG 2>&1
    echo ""
}

# Header
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo -e "${BLUE}📊 Утренний дайджест маркетплейсов${NC}"
echo "$(get_date_ru)"
echo "═══════════════════════════════════════════════════════════════"

if [[ "$PLATFORM" == "all" ]]; then
    for p in ozon wb ymarket; do
        run_digest_for_platform "$p"
    done
else
    run_digest_for_platform "$PLATFORM"
fi

echo "═══════════════════════════════════════════════════════════════"
echo -e "${GREEN}✅ Дайджест готов!${NC}"
echo ""
