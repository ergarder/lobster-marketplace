#!/usr/bin/env bash
set -euo pipefail

THRESHOLD="${1:-15}"

if ! [[ "$THRESHOLD" =~ ^[0-9]+$ ]]; then
  echo "ERROR: threshold должен быть числом, получено: $THRESHOLD" >&2
  exit 1
fi

ENV_FILE="$HOME/.openclaw/marketplace/ozon.env"
REPORT_DIR="$HOME/lobster-marketplace/lobster/logs"
DATE_NOW="$(date '+%Y-%m-%d %H:%M')"
REPORT_FILE="$REPORT_DIR/daily_ozon_report_$(date '+%Y-%m-%d').txt"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: Ozon env file not found: $ENV_FILE" >&2
  exit 1
fi

source "$ENV_FILE"

if [[ -z "${OZON_CLIENT_ID:-}" || -z "${OZON_API_KEY:-}" ]]; then
  echo "ERROR: Ozon credentials are empty" >&2
  exit 1
fi

mkdir -p "$REPORT_DIR"

echo "🔄 Получаю цены Ozon..."

prices_json="$(curl -sS --connect-timeout 10 --max-time 30 -X POST "https://api-seller.ozon.ru/v5/product/info/prices" \
  -H "Client-Id: $OZON_CLIENT_ID" \
  -H "Api-Key: $OZON_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"filter":{"visibility":"ALL"},"limit":1000}')"

echo "🔄 Получаю остатки Ozon..."

stocks_json="$(curl -sS --connect-timeout 10 --max-time 30 -X POST "https://api-seller.ozon.ru/v4/product/info/stocks" \
  -H "Client-Id: $OZON_CLIENT_ID" \
  -H "Api-Key: $OZON_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"filter":{"visibility":"ALL"},"limit":1000}')"

echo "🧮 Формирую отчет..."

tmp_prices="$(mktemp)"
tmp_stocks="$(mktemp)"

echo "$prices_json" > "$tmp_prices"
echo "$stocks_json" > "$tmp_stocks"

jq -n -r \
  --slurpfile prices "$tmp_prices" \
  --slurpfile stocks "$tmp_stocks" \
  --arg date_now "$DATE_NOW" \
  --arg threshold "$THRESHOLD" '
  ($threshold | tonumber) as $threshold_num |

  def fbo_present:
    ([.stocks[]? | select(.type == "fbo") | .present] | add) // 0;

  def fbo_reserved:
    ([.stocks[]? | select(.type == "fbo") | .reserved] | add) // 0;

  ($prices[0].items // []) as $price_items |
  ($stocks[0].items // []) as $stock_items |

  ($price_items | map({key: .offer_id, value: .}) | from_entries) as $price_map |

  ($stock_items | map({
    offer_id: .offer_id,
    product_id: .product_id,
    stock: fbo_present,
    reserved: fbo_reserved,
    price: (($price_map[.offer_id].price.price // 0) | tonumber),
    marketing_price: (($price_map[.offer_id].price.marketing_seller_price // 0) | tonumber),
    min_price: (($price_map[.offer_id].price.min_price // 0) | tonumber),
    commission_fbo: (($price_map[.offer_id].commissions.sales_percent_fbo // 0) | tonumber)
  })) as $rows |

  ($rows | length) as $total_sku |
  ($rows | map(select(.stock == 0))) as $zero_rows |
  ($rows | map(select(.stock > 0 and .stock < $threshold_num))) as $low_rows |
  ($rows | map(select(.price != .marketing_price and .marketing_price > 0))) as $price_diff_rows |

  "🦞 Lobster / Ozon / Elevator",
  "Дата: \($date_now)",
  "",
  "📦 Остатки",
  "Всего SKU: \($total_sku)",
  "Нулевой остаток: \($zero_rows | length)",
  "Низкий остаток < \($threshold_num) шт: \($low_rows | length)",
  "",
  "🚨 Критично — остаток 0:",
  (
    if ($zero_rows | length) == 0 then
      "— нет"
    else
      ($zero_rows[] | "— \(.offer_id): \(.stock) шт, цена продавца \(.price) ₽")
    end
  ),
  "",
  "⚠️ Низкий остаток:",
  (
    if ($low_rows | length) == 0 then
      "— нет"
    else
      ($low_rows[] | "— \(.offer_id): \(.stock) шт, резерв \(.reserved) шт, цена продавца \(.price) ₽")
    end
  ),
  "",
  "💰 Цены с отличием цены продавца от акции:",
  (
    if ($price_diff_rows | length) == 0 then
      "— нет"
    else
      ($price_diff_rows[] | "— \(.offer_id): продавец \(.price) ₽, акция продавца \(.marketing_price) ₽, мин. цена \(.min_price) ₽")
    end
  ),
  "",
  "Что проверить сегодня:",
  "1. SKU с нулевым остатком — риск потери продаж и позиций.",
  "2. SKU с остатком ниже \($threshold_num) шт — подготовить заявку на обжарку/поставку.",
  "3. SKU, где цена акции сильно ниже цены продавца — проверить маржу."
' | tee "$REPORT_FILE"

rm -f "$tmp_prices" "$tmp_stocks"

echo ""
echo "Отчет сохранен: $REPORT_FILE"
