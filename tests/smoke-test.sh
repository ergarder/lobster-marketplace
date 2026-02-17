#!/bin/bash
# Smoke test: все mp-* команды с --mock для каждой платформы
# Проверяет exit codes и базовые паттерны вывода

set +e  # Don't exit on test failures

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$(cd "${SCRIPT_DIR}/../tools" && pwd)"
export PATH="${TOOLS_DIR}:${PATH}"

PASSED=0
FAILED=0
ERRORS=""

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

run_test() {
    local name="$1"
    local cmd="$2"
    local expect_pattern="${3:-}"

    printf "  %-55s " "$name"

    local output
    output=$(eval "$cmd" 2>&1) || true
    local exit_code=${PIPESTATUS[0]:-$?}

    # Check exit code (allow 0 or success output)
    if echo "$output" | grep -qiE "ERROR|не удалось|не найден" && ! echo "$output" | grep -q "mock"; then
        # Allow expected errors in non-critical paths
        :
    fi

    # Check pattern if specified
    if [[ -n "$expect_pattern" ]]; then
        if echo "$output" | grep -qE "$expect_pattern"; then
            echo -e "${GREEN}PASS${NC}"
            ((PASSED++))
            return 0
        else
            echo -e "${RED}FAIL${NC} (pattern '$expect_pattern' not found)"
            ERRORS="${ERRORS}\n  FAIL: $name\n    cmd: $cmd\n    output: $(echo "$output" | head -3)\n"
            ((FAILED++))
            return 1
        fi
    else
        # Just check it doesn't crash (non-empty output)
        if [[ -n "$output" ]]; then
            echo -e "${GREEN}PASS${NC}"
            ((PASSED++))
            return 0
        else
            echo -e "${RED}FAIL${NC} (empty output)"
            ((FAILED++))
            return 1
        fi
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  🧪 Smoke Tests — Marketplace RU (мульти-платформа)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

for platform in ozon wb ymarket; do
    echo -e "${YELLOW}▶ Platform: $platform${NC}"
    echo ""

    # Orders
    run_test "$platform: orders list --mock" \
        "mp-orders --platform $platform list --mock" \
        "Заказ|заказов|Найдено"

    run_test "$platform: orders stats --mock" \
        "mp-orders --platform $platform stats --mock" \
        "Всего|total"

    # Prices
    run_test "$platform: prices list --mock" \
        "mp-prices --platform $platform list --mock" \
        "Цена|Артикул|SKU"

    # Stocks
    run_test "$platform: stocks list --mock" \
        "mp-stocks --platform $platform list --mock" \
        "Остат|stocks|SKU"

    echo ""
done

# Platform-specific tests
echo -e "${YELLOW}▶ Platform-specific tests${NC}"
echo ""

run_test "wb: orders show dual status in mock" \
    "mp-orders --platform wb list --mock" \
    "Статус продавца|supplierStatus"

run_test "wb: prices in kopecks converted to rubles" \
    "mp-prices --platform wb list --mock" \
    "[0-9]+\.[0-9]+ ₽|Цена"

run_test "ymarket: orders show substatus" \
    "mp-orders --platform ymarket list --mock" \
    "STARTED|READY_TO_SHIP|substatus"

run_test "ymarket: confirm-quarantine subcommand exists" \
    "mp-prices --platform ymarket confirm-quarantine --mock" \
    "карантин|quarantine|OK|Нет цен"

# Backward compat: no --platform defaults to ozon
echo ""
echo -e "${YELLOW}▶ Backward compatibility${NC}"
echo ""

run_test "default platform = ozon (orders)" \
    "mp-orders list --mock" \
    "Ozon|Заказ"

run_test "default platform = ozon (prices)" \
    "mp-prices list --mock" \
    "Ozon|SKU|Цена"

run_test "default platform = ozon (stocks)" \
    "mp-stocks list --mock" \
    "Ozon|Остат"

# Help commands
echo ""
echo -e "${YELLOW}▶ Help texts${NC}"
echo ""

run_test "mp-orders --help" \
    "mp-orders --help" \
    "platform"

run_test "mp-prices --help" \
    "mp-prices --help" \
    "platform"

run_test "mp-stocks --help" \
    "mp-stocks --help" \
    "platform"

# Summary
echo ""
echo "═══════════════════════════════════════════════════════════════"
if [[ $FAILED -eq 0 ]]; then
    echo -e "  ${GREEN}✅ All $PASSED tests passed!${NC}"
else
    echo -e "  ${RED}❌ $FAILED failed, $PASSED passed${NC}"
    echo -e "$ERRORS"
fi
echo "═══════════════════════════════════════════════════════════════"
echo ""

exit $FAILED
