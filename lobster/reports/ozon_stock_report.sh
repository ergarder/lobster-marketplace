#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-low}"
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

tmp_stocks="$(mktemp)"
echo "$stocks_json" > "$tmp_stocks"

jq -n -r \
  --slurpfile stocks "$tmp_stocks" \
  --arg mode "$MODE" \
  --arg threshold "$THRESHOLD" '
  ($threshold | tonumber) as $threshold_num |

  def fbo_present:
    ([.stocks[]? | select(.type == "fbo") | .present] | add) // 0;

  def fbo_reserved:
    ([.stocks[]? | select(.type == "fbo") | .reserved] | add) // 0;

  ($stocks[0].items // [] | map({
    offer_id: .offer_id,
    product_id: .product_id,
    stock: fbo_present,
    reserved: fbo_reserved
  })) as $rows |

  ($rows | map(select(.stock == 0))) as $zero_rows |
  ($rows | map(select(.stock > 0 and .stock < $threshold_num))) as $low_rows |
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

rm -f "$tmp_stocks"
