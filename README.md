# OpenClaw Marketplace RU

AI-ассистент для управления продажами на российских маркетплейсах через OpenClaw.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![OpenClaw](https://img.shields.io/badge/OpenClaw-0.8.0+-blue.svg)](https://openclaw.ai)

## Поддерживаемые платформы

| Платформа | Заказы | Цены | Остатки | Особенности |
|-----------|--------|------|---------|-------------|
| **Ozon** | FBS/FBO | Рубли | По складам | Seller API v3/v4 |
| **Wildberries** | FBS | Копейки → рубли | По складам | Dual status, 409=10x penalty |
| **Яндекс Маркет** | FBS | Рубли (RUR) | По кампаниям | Карантин цен, 100+ субстатусов |

## Возможности

- **Мониторинг заказов** — новые заказы, статусы, дедлайны отгрузки на всех площадках
- **Управление ценами** — просмотр и обновление цен с подтверждением, валидацией (±50%), rollback
- **Управление остатками** — контроль остатков на складах, алерты о низких запасах
- **Audit log** — полная история всех изменений цен и остатков с возможностью отката
- **Мульти-платформа** — единый интерфейс для всех маркетплейсов, `--platform` переключает площадку
- **Mock режим** — тестирование без реального API (`--mock`)
- **AI-автоматизация** — утренние дайджесты, мониторинг, умные рекомендации через OpenClaw

## Требования

- **OpenClaw** 0.8.0 или выше
- **jq** — JSON processor
- **curl** — HTTP клиент
- **bash** 3.2+ (macOS default) или 4.0+

### Установка зависимостей

```bash
# macOS
brew install jq curl

# Ubuntu/Debian
sudo apt-get install jq curl

# Alpine Linux
apk add jq curl bash
```

## Установка

### Через OpenClaw Skills (рекомендуется)

```bash
openclaw skills add https://github.com/smvlx/openclaw-marketplace-ru
```

### Ручная установка

```bash
git clone https://github.com/smvlx/openclaw-marketplace-ru.git
cd openclaw-marketplace-ru

# Добавить tools в PATH
export PATH="$PWD/tools:$PATH"

# Или создать симлинки
sudo ln -s $PWD/tools/mp-* /usr/local/bin/
```

## Настройка

Каждая платформа настраивается отдельно через `mp-setup`:

```bash
mp-setup --platform ozon      # Ozon Seller API
mp-setup --platform wb         # Wildberries
mp-setup --platform ymarket    # Яндекс Маркет
```

Без `--platform` по умолчанию настраивается Ozon.

### Ozon

1. [Личный кабинет Ozon Seller](https://seller.ozon.ru/) → Настройки → API ключи
2. Создайте ключ с правами **Admin** или **Content + Analytics**
3. Запустите `mp-setup --platform ozon`, введите **Client ID** (число) и **API Key**

### Wildberries

1. [Кабинет WB](https://seller.wildberries.ru/) → Настройки → API токены
2. Создайте токен с категориями: **Marketplace**, **Content**, **Analytics**
3. Запустите `mp-setup --platform wb`, введите **API Token**

> Разные эндпоинты WB требуют токены разных категорий. Один токен с нужными категориями покрывает все операции.

### Яндекс Маркет

1. [Кабинет Яндекс Маркет](https://partner.market.yandex.ru/) → Настройки → API и модули
2. Создайте токен (макс. 30 на кабинет)
3. Запустите `mp-setup --platform ymarket`, введите **API Key**

> Изменения scope токена вступают в силу через ~10 минут. Business ID и Campaign ID определяются автоматически при первом подключении.

### Проверка подключения

```bash
mp-test --platform ozon
mp-test --platform wb
mp-test --platform ymarket
```

Credentials хранятся в `~/.openclaw/marketplace/` с правами 0600:
- `ozon.env` — Ozon credentials
- `wb.env` — Wildberries credentials
- `ymarket.env` — Яндекс Маркет credentials

## Использование

Все команды принимают `--platform ozon|wb|ymarket` (по умолчанию `ozon`) и `--mock` для тестирования.

### Заказы

```bash
# Показать заказы
mp-orders list --platform ozon
mp-orders list --platform wb
mp-orders list --platform ymarket

# Статус конкретного заказа
mp-orders status 12345678-0001-1                    # Ozon: posting number
mp-orders status 987654321 --platform wb             # WB: числовой ID
mp-orders status 77001122 --platform ymarket         # YM: order ID

# Статистика
mp-orders stats --platform wb

# Mock режим
mp-orders list --mock
```

### Цены

```bash
# Получить цену
mp-prices get TWS-PRO-001
mp-prices get 12345678 --platform wb              # WB: nmID (число)
mp-prices get TWS-PRO-001 --platform ymarket

# Обновить цену (с подтверждением)
mp-prices update TWS-PRO-001 2500
mp-prices update 12345678 1999 --platform wb      # ввод в рублях, конвертация в копейки автоматически
mp-prices update TWS-PRO-001 2500 --platform ymarket

# Со старой ценой (Ozon: зачёркнутая цена)
mp-prices update TWS-PRO-001 2500 --old-price 2999

# Автоподтверждение (только для изменений ≤50%)
mp-prices update TWS-PRO-001 2500 --yes

# Показать все цены
mp-prices list --platform wb

# Яндекс Маркет: карантин цен (при изменении >5%)
mp-prices confirm-quarantine --platform ymarket
```

**Защита от ошибок:**
- Изменение > ±50% требует дополнительного подтверждения
- `--yes` не работает для изменений > 50% (нужен `--force`)
- Цена не может быть 0

### Остатки

```bash
# Все остатки
mp-stocks list
mp-stocks list --platform wb
mp-stocks list --platform ymarket

# Товары с низкими остатками
mp-stocks list --low                        # < 10 шт (по умолчанию)
mp-stocks list --low --threshold 5          # < 5 шт

# Конкретный товар
mp-stocks get TWS-PRO-001

# Обновить остаток
mp-stocks update TWS-PRO-001 100
mp-stocks update 2000000000011 50 --platform wb --warehouse 507921  # WB требует warehouse ID
mp-stocks update TWS-PRO-001 100 --platform ymarket
```

> **WB:** для обновления остатков обязателен `--warehouse <id>`. Список складов: `mp-stocks list --platform wb`.
>
> **Яндекс Маркет:** SKU чувствителен к регистру и отступам.

### Audit Log и Rollback

Все изменения цен и остатков записываются в audit log:

```bash
# История изменений
mp-prices history                              # Последние 20 записей
mp-prices history --sku TWS-PRO-001            # История SKU
mp-prices history --last 50                    # Последние 50
mp-stocks history                              # История остатков

# Rollback
mp-prices rollback --last                      # Откатить последний batch
mp-prices rollback 20260216-143022-a1b2c3d4    # По конкретному ID
mp-stocks rollback --last --mock               # Тест в mock режиме
```

Формат audit log: `TIMESTAMP|USER|PLATFORM|BATCH_ID|ACTION|SKU|OLD_VALUE|NEW_VALUE|STATUS`

**Важно:**
- Rollback всегда требует ручного подтверждения
- Нельзя откатить batch с ошибками (все записи должны быть `success`)
- Нельзя откатить rollback (защита от цикличности)
- Ротация: записи старше 90 дней удаляются автоматически

### Утренний дайджест

```bash
# Все платформы
./examples/morning-digest.sh --platform all

# Конкретная платформа
./examples/morning-digest.sh --platform wb

# Тест
./examples/morning-digest.sh --platform all --mock
```

### Примеры для AI-ассистента

```
👤 Покажи заказы на всех площадках
🤖 [Запускает mp-orders для каждой платформы]
   📦 Ozon: 3 заказа (2 ожидают сборки)
   📦 WB: 5 заказов (3 новых)
   📦 Яндекс: 2 заказа (1 в обработке)

👤 Подними цену на TWS-PRO-001 до 2500 на Ozon
🤖 Текущая цена: 1999 ₽ → Новая: 2500 ₽ (+25.06%)
   Подтвердить? (y/N)

👤 Какие товары заканчиваются на WB?
🤖 [Запускает mp-stocks list --low --platform wb]
   ⚠️ 2 товара с низкими остатками...
```

## Batch Rate Limiting

Массовые операции автоматически разбиваются на чанки:

- **Chunk size:** 10 (настраивается через `BATCH_SIZE`)
- **Delay:** 1 секунда между чанками (`BATCH_DELAY`)
- **Rate limit handling:** Exponential backoff (5s → 15s → 30s)
- **Progress:** `[30/100] Обработано... ETA: 7s`

## Тестирование

```bash
# Smoke tests (все платформы, mock режим)
bash tests/smoke-test.sh
```

Все 22 теста покрывают: заказы, цены, остатки для каждой платформы, платформо-специфичные особенности, обратную совместимость и help тексты.

## Безопасность

- **Credentials хранятся локально** в `~/.openclaw/marketplace/*.env` с правами 0600
- **Валидация при загрузке** — credentials файлы проверяются на отсутствие shell-инъекций перед source
- **Маскировка в логах** — API ключи никогда не логируются в открытом виде
- **curl stderr подавлен** — ошибки curl не могут случайно утечь с токенами
- **JSON через jq** — все JSON данные для API строятся через `jq -n`, исключая инъекции
- **Audit log с flock** — атомарная запись и ротация через flock
- **Не коммитить в git** — `.gitignore` исключает `*.env`, `logs/`, `*.log`

## Архитектура

```
tools/                     # 5 CLI entry points
  mp-setup                 # Настройка credentials
  mp-test                  # Проверка подключения
  mp-orders                # Управление заказами
  mp-prices                # Управление ценами
  mp-stocks                # Управление остатками

lib/common/                # Общие модули
  platform.sh              # Диспетчер платформ, валидация, загрузка credentials
  logger.sh                # Логирование с маскировкой
  http.sh                  # HTTP retry, batch executor
  audit.sh                 # Audit log, rollback
  formatter.sh             # JSON→текст, валидация цен, конвертация валют

lib/ozon/                  # Ozon Seller API
lib/wb/                    # Wildberries API
lib/ymarket/               # Яндекс Маркет Partner API
  auth.sh                  # Credentials: загрузка, сохранение, проверка
  http.sh                  # HTTP клиент с platform-specific headers
  orders.sh                # Заказы
  prices.sh                # Цены
  stocks.sh                # Остатки
```

Каждая платформа реализует одинаковый набор из 5 модулей. CLI tools используют диспетчер `platform.sh` для вызова нужной реализации.

## Troubleshooting

### Credentials не настроены

```
ERROR: Ozon credentials не настроены
ERROR: WB API токен не настроен
ERROR: Яндекс Маркет API ключ не настроен
```

**Решение:** `mp-setup --platform <ozon|wb|ymarket>`

### 401 — Неверные credentials

**Причины:** неправильный ключ, ключ деактивирован.
**Решение:** создайте новый ключ в ЛК площадки и обновите через `mp-setup`.

### 403 — Доступ запрещён

**Причина:** ключ не имеет нужных прав/категорий.
**Решение:**
- **Ozon:** пересоздайте ключ с правами Admin или Content + Analytics
- **WB:** проверьте что токен имеет нужные категории (Marketplace, Content, Analytics)
- **YM:** проверьте scope токена (изменения вступают через ~10 минут)

### 429 / 420 — Rate limit

**Причина:** слишком много запросов.
**Решение:** система автоматически повторяет запрос с exponential backoff. Если не помогает — подождите 60 секунд.

> WB: код 409 считается за 10 запросов к лимиту.
> YM: использует код 420 (не 429) для rate limit.

### jq: command not found

```bash
brew install jq      # macOS
sudo apt install jq  # Ubuntu/Debian
```

## Документация API

- [Ozon Seller API](https://docs.ozon.ru/api/seller/)
- [Wildberries API](https://openapi.wildberries.ru/)
- [Яндекс Маркет Partner API](https://yandex.ru/dev/market/partner-api/)
- [OpenClaw Documentation](https://docs.openclaw.ai/)

## Roadmap

- [x] **v0.1.0** — Ozon MVP: заказы, цены, остатки (FBS)
- [x] **v0.2.0** — Wildberries: заказы, цены, остатки, dual status
- [x] **v0.3.0** — Яндекс Маркет: заказы, цены, остатки, карантин цен
- [x] **v0.4.0** — Интеграция: audit log, rollback, smoke tests, мульти-платформа CLI
- [x] **v0.5.0** — Security audit: safe credentials, jq JSON, bash 3.2 compat
- [ ] **v0.6.0** — Финансовые отчёты, аналитика продаж
- [ ] **v0.7.0** — Отзывы и ответы на отзывы
- [ ] **v1.0.0** — Кросс-маркетплейс сравнение и аналитика

## Вклад в проект

Contributions are welcome!

1. Fork репозиторий
2. Создайте feature branch (`git checkout -b feature/amazing-feature`)
3. Commit изменения (`git commit -m 'Add amazing feature'`)
4. Push в branch (`git push origin feature/amazing-feature`)
5. Создайте Pull Request

## Лицензия

MIT License — см. [LICENSE](LICENSE)

## Автор

**Alex** ([@smvlx](https://github.com/smvlx))

## Благодарности

- [OpenClaw](https://openclaw.ai/) — AI platform
- [Ozon](https://ozon.ru/), [Wildberries](https://wildberries.ru/), [Яндекс Маркет](https://market.yandex.ru/) — маркетплейсы

---

**Нужна помощь?** Создайте [issue](https://github.com/smvlx/openclaw-marketplace-ru/issues) или напишите в [discussions](https://github.com/smvlx/openclaw-marketplace-ru/discussions).
