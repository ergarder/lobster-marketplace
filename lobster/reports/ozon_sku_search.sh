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

catalog_json="$(curl -sS --connect-timeout 10 --max-time 30 -X POST "https://api-seller.ozon.ru/v3/product/list" \
  -H "Client-Id: $OZON_CLIENT_ID" \
  -H "Api-Key: $OZON_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"filter":{"visibility":"ALL"},"limit":1000}')"

offer_ids_json="$(echo "$catalog_json" | jq -c '[ (.result.items // .items // [])[] | .offer_id | select(. != null) ]')"

if [[ "$offer_ids_json" == "[]" || -z "$offer_ids_json" ]]; then
  echo "ERROR: Ozon product list returned no offer_id" >&2
  echo "$catalog_json" >&2
  exit 1
fi

info_payload="$(jq -n --argjson offer_id "$offer_ids_json" '{offer_id: $offer_id}')"

product_info_json="$(curl -sS --connect-timeout 10 --max-time 60 -X POST "https://api-seller.ozon.ru/v3/product/info/list" \
  -H "Client-Id: $OZON_CLIENT_ID" \
  -H "Api-Key: $OZON_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$info_payload")"

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

tmp_catalog="$(mktemp)"
tmp_info="$(mktemp)"
tmp_prices="$(mktemp)"
tmp_stocks="$(mktemp)"

echo "$catalog_json" > "$tmp_catalog"
echo "$product_info_json" > "$tmp_info"
echo "$prices_json" > "$tmp_prices"
echo "$stocks_json" > "$tmp_stocks"

jq -n -r \
  --slurpfile catalog "$tmp_catalog" \
  --slurpfile info "$tmp_info" \
  --slurpfile prices "$tmp_prices" \
  --slurpfile stocks "$tmp_stocks" \
  --arg query "$QUERY" '
  def normalize_search:
    tostring
    | ascii_downcase
    | gsub("А";"а") | gsub("Б";"б") | gsub("В";"в") | gsub("Г";"г") | gsub("Д";"д")
    | gsub("Е";"е") | gsub("Ё";"е") | gsub("Ж";"ж") | gsub("З";"з") | gsub("И";"и")
    | gsub("Й";"й") | gsub("К";"к") | gsub("Л";"л") | gsub("М";"м") | gsub("Н";"н")
    | gsub("О";"о") | gsub("П";"п") | gsub("Р";"р") | gsub("С";"с") | gsub("Т";"т")
    | gsub("У";"у") | gsub("Ф";"ф") | gsub("Х";"х") | gsub("Ц";"ц") | gsub("Ч";"ч")
    | gsub("Ш";"ш") | gsub("Щ";"щ") | gsub("Ъ";"ъ") | gsub("Ы";"ы") | gsub("Ь";"ь")
    | gsub("Э";"э") | gsub("Ю";"ю") | gsub("Я";"я")
    | gsub("ё";"е");

  def fbo_present:
    ([.stocks[]? | select(.type == "fbo") | .present] | add) // 0;

  def fbo_reserved:
    ([.stocks[]? | select(.type == "fbo") | .reserved] | add) // 0;

  ($query | normalize_search) as $q |

  ($catalog[0].result.items // $catalog[0].items // []) as $catalog_items |
  ($info[0].result.items // $info[0].items // []) as $info_items |
  ($prices[0].items // []) as $price_items |
  ($stocks[0].items // []) as $stock_items |

  ($info_items | map({
    key: (.offer_id | tostring),
    value: {
      offer_id: (.offer_id | tostring),
      product_id: (.id // .product_id // "" | tostring),
      name: ((.name // "") | tostring)
    }
  }) | from_entries) as $info_map |

  ($catalog_items | map({
    key: (.offer_id | tostring),
    value: {
      offer_id: (.offer_id | tostring),
      product_id: (.product_id // .id // "" | tostring),
      name: (($info_map[(.offer_id | tostring)].name // "") | tostring)
    }
  }) | from_entries) as $catalog_map |

  ($price_items | map({
    key: (.offer_id | tostring),
    value: .
  }) | from_entries) as $price_map |

  ($stock_items | map({
    offer_id: (.offer_id | tostring),
    product_id: (.product_id | tostring),
    name: (($catalog_map[(.offer_id | tostring)].name // $info_map[(.offer_id | tostring)].name // "") | tostring),
    stock: fbo_present,
    reserved: fbo_reserved,
    price: (($price_map[(.offer_id | tostring)].price.price // 0) | tonumber),
    marketing_price: (($price_map[(.offer_id | tostring)].price.marketing_seller_price // 0) | tonumber),
    min_price: (($price_map[(.offer_id | tostring)].price.min_price // 0) | tonumber),
    old_price: (($price_map[(.offer_id | tostring)].price.old_price // 0) | tonumber),
    commission_fbo: (($price_map[(.offer_id | tostring)].commissions.sales_percent_fbo // 0) | tonumber)
  })) as $stock_rows |

  ($catalog_items | map({
    offer_id: (.offer_id | tostring),
    product_id: (.product_id // .id // "" | tostring),
    name: (($info_map[(.offer_id | tostring)].name // "") | tostring),
    stock: 0,
    reserved: 0,
    price: (($price_map[(.offer_id | tostring)].price.price // 0) | tonumber),
    marketing_price: (($price_map[(.offer_id | tostring)].price.marketing_seller_price // 0) | tonumber),
    min_price: (($price_map[(.offer_id | tostring)].price.min_price // 0) | tonumber),
    old_price: (($price_map[(.offer_id | tostring)].price.old_price // 0) | tonumber),
    commission_fbo: (($price_map[(.offer_id | tostring)].commissions.sales_percent_fbo // 0) | tonumber)
  })) as $catalog_rows |

  (($stock_rows + $catalog_rows)
    | unique_by(.offer_id)
    | map(select(
      ((.offer_id | normalize_search) | contains($q)) or
      ((.product_id | normalize_search) | contains($q)) or
      ((.name | normalize_search) | contains($q))
    ))
  ) as $matches |

  if ($matches | length) == 0 then
    "📦 SKU не найден",
    "",
    "Запрос: \($query)",
    "",
    "Поиск работает по названию, offer_id и product_id.",
    "Пример: колумбия, бразилия, brazil, FBR, 3549918769"
  else
    "📦 Найдено SKU: \($matches | length)",
    "",
    (
      $matches[0:10][] |
      "— \((if (.name // "") == "" then "Без названия" else (.name // "")[0:90] end))",
      "  Offer ID: \(.offer_id)",
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
        "Показаны первые 10 совпадений. Уточни запрос."
      else
        empty
      end
    )
  end
'

rm -f "$tmp_catalog" "$tmp_info" "$tmp_prices" "$tmp_stocks"
