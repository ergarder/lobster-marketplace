#!/usr/bin/env bash
set -euo pipefail

QUERY="${1:-}"

if [[ -z "$QUERY" ]]; then
  echo "ERROR: query is empty" >&2
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

prices_json="$(curl -sS --connect-timeout 10 --max-time 30 -X POST "https://api-seller.ozon.ru/v5/product/info/prices" \
  -H "Client-Id: $OZON_CLIENT_ID" \
  -H "Api-Key: $OZON_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"filter":{"visibility":"ALL"},"limit":1000}')"

stocks_json="$(curl -sS --connect-timeout 10 --max-time 30 -X POST "https://api-seller.ozon.ru/v4/product/info/stocks" \
  -H "Client-Id: $OZON_CLIENT_ID" \
  -H "Api-Key: $OZON_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"filter":{"visibility":"ALL"},"limit":1000}')"

tmp_prices="$(mktemp)"
tmp_stocks="$(mktemp)"

echo "$prices_json" > "$tmp_prices"
echo "$stocks_json" > "$tmp_stocks"

jq -n -r \
  --slurpfile prices "$tmp_prices" \
  --slurpfile stocks "$tmp_stocks" \
  --arg query "$QUERY" '
  def fbo_present:
    ([.stocks[]? | select(.type == "fbo") | .present] | add) // 0;

  def fbo_reserved:
    ([.stocks[]? | select(.type == "fbo") | .reserved] | add) // 0;

  ($query | ascii_downcase) as $q |

  ($prices[0].items // []) as $price_items |
  ($stocks[0].items // []) as $stock_items |

  ($price_items | map({
    key: (.offer_id | tostring),
    value: .
  }) | from_entries) as $price_map |

  ($stock_items | map({
    offer_id: (.offer_id | tostring),
    product_id: (.product_id | tostring),
    stock: fbo_present,
    reserved: fbo_reserved,
    price: (($price_map[(.offer_id | tostring)].price.price // 0) | tonumber),
    marketing_price: (($price_map[(.offer_id | tostring)].price.marketing_seller_price // 0) | tonumber),
    min_price: (($price_map[(.offer_id | tostring)].price.min_price // 0) | tonumber),
    old_price: (($price_map[(.offer_id | tostring)].price.old_price // 0) | tonumber),
    commission_fbo: (($price_map[(.offer_id | tostring)].commissions.sales_percent_fbo // 0) | tonumber)
  })) as $rows |

  ($rows | map(select(
    ((.offer_id | ascii_downcase) | contains($q)) or
    ((.product_id | ascii_downcase) | contains($q))
  ))) as $matches |

  if ($matches | length) == 0 then
    "📦 SKU не найден",
    "",
    "Запрос: \($query)",
    "",
    "Сейчас поиск работает по offer_id и product_id.",
    "Пример: FBR или 3549918769"
  else
    "📦 Найдено SKU: \($matches | length)",
    "",
    (
      $matches[0:10][] |
      "— Offer ID: \(.offer_id)",
      "  Product ID: \(.product_id)",
      "  Остаток FBO: \(.stock) шт",
      "  Резерв FBO: \(.reserved) шт",
      "  Цена продавца: \(.price) ₽",
      "  Акционная цена: \(.marketing_price) ₽",
      "  Мин. цена: \(.min_price) ₽",
      "  Комиссия FBO: \(.commission_fbo)%",
      ""
    ),
    (
      if ($matches | length) > 10 then
        "Показаны первые 10 совпадений."
      else
        empty
      end
    )
  end
'

rm -f "$tmp_prices" "$tmp_stocks"
