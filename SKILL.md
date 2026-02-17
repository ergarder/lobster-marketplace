# Marketplace RU — Ozon / Wildberries / Яндекс Маркет

Skill для управления продажами на маркетплейсах через AI-ассистента.

## Поддерживаемые платформы

| Платформа | Флаг | Статус |
|-----------|------|--------|
| Ozon | `--platform ozon` (по умолчанию) | ✅ |
| Wildberries | `--platform wb` | ✅ |
| Яндекс Маркет | `--platform ymarket` | ✅ |

## Описание

Этот skill позволяет OpenClaw агенту управлять магазинами на маркетплейсах:
- Мониторить заказы и дедлайны отгрузки
- Обновлять цены с контролем изменений
- Управлять остатками на складах
- Получать аналитику и алерты

## Требования

### Ozon
- API ключи (Client-Id + Api-Key) с правами Admin
- `mp-setup --platform ozon`

### Wildberries
- API токен с категориями: Marketplace, Content, Analytics
- ⚠️ Разные эндпоинты требуют токены разных категорий!
- `mp-setup --platform wb`

### Яндекс Маркет
- API Key (из кабинета → Настройки → API и модули)
- ⚠️ Изменения scope токена: ~10 минут задержка
- `mp-setup --platform ymarket`

## Команды

Все команды принимают `--platform ozon|wb|ymarket` (по умолчанию `ozon`).
Все команды поддерживают `--mock` для тестирования без реального API.

### 🛠️ Настройка

```
mp-setup --platform ozon      # настроить Ozon
mp-setup --platform wb         # настроить Wildberries
mp-setup --platform ymarket    # настроить Яндекс Маркет
mp-test --platform wb          # проверить подключение
```

### 📦 Заказы

```
mp-orders list --platform wb --mock
mp-orders status 987654321 --platform wb
mp-orders stats --platform ymarket
```

**Особенности по платформам:**
- **WB**: Двойной статус (supplierStatus + wbStatus), цены в копейках
- **YM**: Подстатусы (100+ значений), ISO даты с timezone

### 💰 Цены

```
mp-prices get TWS-PRO-001 --platform wb
mp-prices update TWS-PRO-001 2500 --platform wb    # цена в рублях
mp-prices list --platform ymarket
mp-prices confirm-quarantine --platform ymarket     # только YM!
```

**Особенности:**
- **WB**: Цены хранятся в копейках. Вводите в рублях — конвертация автоматическая.
- **YM**: После обновления цены автоматически проверяется карантин. При резком изменении (>5%) цена может быть задержана. Используйте `confirm-quarantine` для подтверждения.
- **YM**: Валюта в API — `RUR` (не `RUB`).

### 📊 Остатки

```
mp-stocks list --platform wb --mock
mp-stocks update SKU123 100 --platform wb --warehouse 507921
mp-stocks get TWS-PRO-001 --platform ymarket
```

**Особенности:**
- **WB**: Остатки привязаны к складу. Используйте `--warehouse <id>`. Список складов кэшируется автоматически.
- **YM**: SKU чувствителен к регистру и padding (`"557722" ≠ "0557722"`). Макс. 2000 SKU за запрос.

### 🔄 Откат изменений

```
mp-prices rollback --last --platform wb
mp-stocks rollback BATCH_ID --platform ymarket
mp-prices history --sku TWS-PRO-001
```

### 📊 Утренний дайджест

```bash
./examples/morning-digest.sh --platform all --mock    # все платформы
./examples/morning-digest.sh --platform wb             # только WB
```

## Обработка ошибок

| Код | Ozon | WB | YM |
|-----|------|----|----|
| Rate limit | 429 | 429 (+ 409=10x) | **420** |
| Auth | 401/403 | 401/403 | 401/403 |
| Not found | 404 | 404 | 404 (проверьте businessId/campaignId!) |

## Безопасность

- Credentials хранятся в `~/.openclaw/marketplace/{ozon,wb,ymarket}.env` с правами 600
- Все изменения цен/остатков записываются в audit log с полем `PLATFORM`
- Подтверждение перед любым обновлением (можно `--yes` для автоматизации, но >50% блокируется)
- Race condition detection: повторная проверка перед записью
