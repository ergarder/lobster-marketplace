#!/bin/bash
# Пример утреннего дайджеста по заказам и остаткам Ozon
# 
# Использование:
#   ./morning-digest.sh
#   ./morning-digest.sh --mock  # тестирование с mock данными

set -e

# Определить директорию скрипта
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$(cd "${SCRIPT_DIR}/../tools" && pwd)"

# Проверить наличие команд
if ! command -v mp-orders &> /dev/null; then
    echo "ERROR: mp-orders не найден в PATH"
    echo "Добавьте tools/ в PATH или запустите из корня репозитория"
    exit 1
fi

# Парсинг аргументов
MOCK_FLAG=""
if [[ "${1:-}" == "--mock" ]]; then
    MOCK_FLAG="--mock"
fi

# Цвета для вывода
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция для получения даты на русском
get_date_ru() {
    # Месяцы на русском
    case $(date +%m) in
        01) month="января" ;;
        02) month="февраля" ;;
        03) month="марта" ;;
        04) month="апреля" ;;
        05) month="мая" ;;
        06) month="июня" ;;
        07) month="июля" ;;
        08) month="августа" ;;
        09) month="сентября" ;;
        10) month="октября" ;;
        11) month="ноября" ;;
        12) month="декабря" ;;
    esac
    
    # Дни недели на русском
    case $(date +%u) in
        1) weekday="Понедельник" ;;
        2) weekday="Вторник" ;;
        3) weekday="Среда" ;;
        4) weekday="Четверг" ;;
        5) weekday="Пятница" ;;
        6) weekday="Суббота" ;;
        7) weekday="Воскресенье" ;;
    esac
    
    echo "$weekday, $(date +%d) $month $(date +%Y)"
}

# Заголовок
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo -e "${BLUE}📊 Утренний дайджест Ozon${NC}"
echo "$(get_date_ru)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Раздел 1: Новые заказы
echo -e "${BLUE}📦 Новые и активные заказы${NC}"
echo "─────────────────────────────────────────────────────────────"
echo ""

ORDERS_OUTPUT=$(mp-orders list $MOCK_FLAG 2>&1)
ORDERS_RESULT=$?

if [[ $ORDERS_RESULT -eq 0 ]]; then
    # Показать только первые 10 заказов (чтобы не переполнить вывод)
    echo "$ORDERS_OUTPUT" | head -50
    
    # Подсчитать количество заказов с дедлайном сегодня
    TODAY=$(date +%Y-%m-%d)
    
    echo ""
    echo -e "${YELLOW}💡 Рекомендации:${NC}"
    echo "• Проверьте заказы со статусом 'awaiting_packaging'"
    echo "• Обратите внимание на дедлайны отгрузки"
else
    echo -e "${YELLOW}⚠️ Не удалось получить заказы${NC}"
    echo "$ORDERS_OUTPUT"
fi

echo ""
echo ""

# Раздел 2: Товары с низкими остатками
echo -e "${BLUE}⚠️  Товары с низкими остатками (< 10 шт)${NC}"
echo "─────────────────────────────────────────────────────────────"
echo ""

STOCKS_OUTPUT=$(mp-stocks list --low $MOCK_FLAG 2>&1)
STOCKS_RESULT=$?

if [[ $STOCKS_RESULT -eq 0 ]]; then
    # Проверить есть ли товары с низкими остатками
    if echo "$STOCKS_OUTPUT" | grep -q "Нет данных об остатках"; then
        echo "✅ Все товары имеют достаточный запас"
    else
        echo "$STOCKS_OUTPUT"
        echo ""
        echo -e "${YELLOW}💡 Рекомендация: Пополните остатки товаров с низким запасом${NC}"
    fi
else
    echo -e "${YELLOW}⚠️ Не удалось получить остатки${NC}"
    echo "$STOCKS_OUTPUT"
fi

echo ""
echo ""

# Раздел 3: Статистика
echo -e "${BLUE}📊 Краткая статистика${NC}"
echo "─────────────────────────────────────────────────────────────"
echo ""

STATS_OUTPUT=$(mp-orders stats $MOCK_FLAG 2>&1)
STATS_RESULT=$?

if [[ $STATS_RESULT -eq 0 ]]; then
    echo "$STATS_OUTPUT"
else
    echo -e "${YELLOW}⚠️ Не удалось получить статистику${NC}"
fi

echo ""

# Футер
echo "═══════════════════════════════════════════════════════════════"
echo -e "${GREEN}✅ Дайджест готов!${NC}"
echo ""
echo "Для получения более детальной информации используйте:"
echo "  mp-orders list              # все заказы"
echo "  mp-orders status <id>       # детали заказа"
echo "  mp-stocks list              # все остатки"
echo "  mp-prices list              # все цены"
echo ""

exit 0
