#!/usr/bin/env bash
set -euo pipefail

REPORT_MODE="${1:-low}"
THRESHOLD="${2:-15}"

if ! [[ "$THRESHOLD" =~ ^[0-9]+$ ]]; then
  echo "ERROR: threshold должен быть числом, получено: $THRESHOLD" >&2
  exit 1
fi

ENV_FILE="$HOME/.openclaw/marketplace/ozon.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: Ozon env file not found: $ENV_FILE" >&2
  exit 1
fi

source "$ENV_FILE"

if [[ -z "${OZON_CLIENT_ID:-}" || -z "${OZON_API_KEY:-}" ]]; then
  echo "ERROR: Ozon credentials are empty" >&2
  exit 1
fi

stocks_json="$(curl -sS --connect-timeout 10 --max-time 30 -X POST "https://api-seller.ozon.ru/v4/product/info/stocks" \
  -H "Client-Id: $OZON_CLIENT_ID" \
  -H "Api-Key: $OZON_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"filter":{"visibility":"ALL"},"limit":1000}')"

prices_json="$(curl -sS --connect-timeout 10 --max-time 30 -X POST "https://api-seller.ozon.ru/v5/product/info/prices" \
  -H "Client-Id: $OZON_CLIENT_ID" \
  -H "Api-Key: $OZON_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"filter":{"visibility":"ALL"},"limit":1000}')"

tmp_stocks="$(mktemp)"
tmp_prices="$(mktemp)"

echo "$stocks_json" > "$tmp_stocks"
echo "$prices_json" > "$tmp_prices"

jq -n -r \
  --slurpfile stocks "$tmp_stocks" \
  --slurpfile prices "$tmp_prices" \
  --arg mode "$REPORT_MODE" \
  --arg threshold "$THRESHOLD" '
  ($threshold | tonumber) as $threshold_num |

  def fbo_present:
    ([.stocks[]? | select(.type == "fbo") | .present] | add) // 0;

  def fbo_reserved:
    ([.stocks[]? | select(.type == "fbo") | .reserved] | add) // 0;

  ($prices[0].items // []) as $price_items |
  ($stocks[0].items // []) as $stock_items |

  ($price_items | map({
    key: (.offer_id | tostring),
    value: {
      price: ((.price.price // 0) | tonumber),
      marketing_price: ((.price.marketing_seller_price // 0) | tonumber),
      min_price: ((.price.min_price // 0) | tonumber),
      old_price: ((.price.old_price // 0) | tonumber),
      commission_fbo: ((.commissions.sales_percent_fbo // 0) | tonumber)
    }
  }) | from_entries) as $price_map |

  ($stock_items | map({
    offer_id: (.offer_id | tostring),
    product_id: (.product_id | tostring),
    stock: fbo_present,
    reserved: fbo_reserved,
    price: (($price_map[(.offer_id | tostring)].price // 0) | tonumber),
    marketing_price: (($price_map[(.offer_id | tostring)].marketing_price // 0) | tonumber),
    min_price: (($price_map[(.offer_id | tostring)].min_price // 0) | tonumber),
    old_price: (($price_map[(.offer_id | tostring)].old_price // 0) | tonumber),
    commission_fbo: (($price_map[(.offer_id | tostring)].commission_fbo // 0) | tonumber),
    has_price_data: ($price_map[(.offer_id | tostring)] != null)
  })) as $rows |

  ($rows | map(select(.stock == 0))) as $zero_rows |
  ($rows | map(select(.stock > 0 and .stock < $threshold_num))) as $low_rows |
  ($rows | map(select(.has_price_data == true and .min_price > 0 and .price > 0 and .price < .min_price))) as $below_min_price_rows |
  (($zero_rows | length) + ($low_rows | length)) as $stock_alerts_count |

  if $mode == "zero" then
    "❌ Закончились",
    "",
    (
      if ($zero_rows | length) == 0 then
        "— нет SKU с нулевым остатком"
      else
        ($zero_rows[] | "— \(.offer_id): \(.stock) шт, резерв \(.reserved) шт")
      end
    )

  elif $mode == "roast" then
    "🔥 Roast request",
    "",
    "Порог низкого остатка: < \($threshold_num) шт",
    "",
    (
      if (($zero_rows + $low_rows) | length) == 0 then
        "— нет SKU для заявки"
      else
        (($zero_rows + $low_rows)[] |
          if .stock == 0 then
            "— \(.offer_id): остаток 0 шт → срочно проверить поставку / обжарку"
          else
            "— \(.offer_id): остаток \(.stock) шт → проверить необходимость обжарки / поставки"
          end
        )
      end
    )

  elif $mode == "alerts" then
    "🚨 Активные алерты",
    "",
    "Всего stock-алертов: \($stock_alerts_count)",
    "— Нулевой остаток: \($zero_rows | length)",
    "— Низкий остаток < \($threshold_num) шт: \($low_rows | length)",
    "",
    "❌ Критично — остаток 0:",
    (
      if ($zero_rows | length) == 0 then
        "— нет"
      else
        ($zero_rows[] | "— \(.offer_id): \(.stock) шт, резерв \(.reserved) шт")
      end
    ),
    "",
    "⚠️ Низкий остаток:",
    (
      if ($low_rows | length) == 0 then
        "— нет"
      else
        ($low_rows[] | "— \(.offer_id): \(.stock) шт, резерв \(.reserved) шт")
      end
    )

  elif $mode == "problem_sku" then
    "📦 Проблемные SKU",
    "",
    "Порог низкого остатка: < \($threshold_num) шт",
    "",
    "Сводка:",
    "— Нулевой остаток: \($zero_rows | length)",
    "— Низкий остаток: \($low_rows | length)",
    "— Цена ниже минимальной: \($below_min_price_rows | length)",
    "",
    "❌ Остаток 0:",
    (
      if ($zero_rows | length) == 0 then
        "— нет"
      else
        ($zero_rows[0:10][] | "— \(.offer_id): остаток \(.stock) шт, резерв \(.reserved) шт, цена \(.price) ₽")
      end
    ),
    "",
    "⚠️ Низкий остаток:",
    (
      if ($low_rows | length) == 0 then
        "— нет"
      else
        ($low_rows[0:10][] | "— \(.offer_id): остаток \(.stock) шт, резерв \(.reserved) шт, цена \(.price) ₽")
      end
    ),
    "",
    "💰 Цена ниже минимальной:",
    (
      if ($below_min_price_rows | length) == 0 then
        "— нет"
      else
        ($below_min_price_rows[0:10][] | "— \(.offer_id): цена \(.price) ₽, мин. цена \(.min_price) ₽")
      end
    )

  elif $mode == "alerts_reports" then
    "📊 Алерты отчетов",
    "",
    "Пока проверяется только наличие Telegram/Ozon отчетного контура.",
    "Следующий этап: проверять наличие файла daily_ozon_report за сегодня и ошибки cron."

  elif $mode == "missing_sku" then
    "📦 SKU без данных",
    "",
    "Пока не подключено.",
    "Следующий этап: сверять список SKU из каталога с ответами Ozon stocks/prices."

  else
    "⚠️ Низкие остатки",
    "",
    "Порог: < \($threshold_num) шт",
    "",
    (
      if ($low_rows | length) == 0 then
        "— нет SKU с низким остатком"
      else
        ($low_rows[] | "— \(.offer_id): \(.stock) шт, резерв \(.reserved) шт")
      end
    )
  end
'

rm -f "$tmp_stocks" "$tmp_prices"
