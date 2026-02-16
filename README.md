# OpenClaw Marketplace RU — Ozon Seller API

AI-ассистент для управления продажами на Ozon маркетплейсе через OpenClaw.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![OpenClaw](https://img.shields.io/badge/OpenClaw-0.8.0+-blue.svg)](https://openclaw.ai)

## 🚀 Возможности

- 📦 **Мониторинг заказов** — новые заказы FBS/FBO, статусы, дедлайны отгрузки
- 💰 **Управление ценами** — просмотр и обновление цен с подтверждением и валидацией
- 📊 **Управление остатками** — контроль остатков на складах, алерты о низких запасах
- ⚡️ **Быстрые команды** — все операции доступны через CLI и AI-ассистента
- 🤖 **AI-автоматизация** — утренние дайджесты, мониторинг, умные рекомендации
- 🔒 **Безопасность** — credentials хранятся локально с правами 0600

## 📋 Требования

- **OpenClaw** 0.8.0 или выше
- **jq** — JSON processor
- **curl** — HTTP клиент
- **bash** 4.0+

### Установка зависимостей

**Ubuntu/Debian:**
```bash
sudo apt-get install jq curl
```

**macOS:**
```bash
brew install jq curl
```

**Alpine Linux:**
```bash
apk add jq curl bash
```

## 🛠️ Установка

### Способ 1: Через OpenClaw Skills (рекомендуется)

```bash
openclaw skills add https://github.com/smvlx/openclaw-marketplace-ru
```

### Способ 2: Ручная установка

```bash
# Клонировать репозиторий
git clone https://github.com/smvlx/openclaw-marketplace-ru.git
cd openclaw-marketplace-ru

# Добавить tools в PATH
export PATH="$PWD/tools:$PATH"

# Или создать симлинки
sudo ln -s $PWD/tools/mp-* /usr/local/bin/
```

## ⚙️ Настройка Ozon API

### Шаг 1: Получить API ключи

1. Зайдите в [личный кабинет Ozon Seller](https://seller.ozon.ru/)
2. Перейдите в **Настройки → API ключи**
3. Нажмите **Создать новый ключ**
4. Укажите название: `OpenClaw Integration`
5. Выберите права:
   - **Admin** (полный доступ) или
   - **Content + Analytics** (минимальные права для MVP)
6. Скопируйте **Client-Id** и **Api-Key**

### Шаг 2: Настроить credentials

```bash
mp-setup
```

Следуйте инструкциям на экране:
- Введите **Client ID** (числовой идентификатор)
- Введите **API Key** (секретный ключ)

Credentials будут сохранены в `~/.openclaw/marketplace/credentials.env` с правами 0600.

### Шаг 3: Проверить подключение

```bash
mp-test
```

Если всё настроено правильно, вы увидите:
```
✅ Ozon API: Подключено
Client ID: 12345
Товаров в каталоге: 150
```

## 📚 Использование

### Команды CLI

#### Заказы

```bash
# Показать новые/активные заказы
mp-orders list

# Статус конкретного заказа
mp-orders status 12345678-0001-1

# Статистика заказов
mp-orders stats

# Тестирование с mock данными (без реального API)
mp-orders list --mock
```

#### Цены

```bash
# Получить текущую цену товара
mp-prices get TWS-PRO-001

# Обновить цену (с подтверждением)
mp-prices update TWS-PRO-001 2500

# Обновить цену со старой ценой (зачёркнутой)
mp-prices update TWS-PRO-001 2500 --old-price 2999

# Показать цены всех товаров
mp-prices list

# Тестирование с mock данными
mp-prices get TWS-PRO-001 --mock
```

**⚠️ ВАЖНО:** Обновление цен всегда требует подтверждения! Система покажет:
- Старую и новую цену
- Процент изменения
- Предупреждение если изменение > ±50%

#### Остатки

```bash
# Показать все остатки
mp-stocks list

# Показать только товары с низкими остатками (< 10 шт)
mp-stocks list --low

# Показать товары с остатком < 5 шт
mp-stocks list --low --threshold 5

# Получить остаток конкретного товара
mp-stocks get TWS-PRO-001

# Обновить остаток
mp-stocks update TWS-PRO-001 100

# Тестирование с mock данными
mp-stocks list --mock
```

### Примеры для AI-ассистента

```
👤 Покажи новые заказы на Ozon
🤖 [Запускает mp-orders list]
   📦 Найдено заказов: 3
   
   Заказ №12345678-0001-1
   📊 Статус: awaiting_packaging
   📦 Товаров: 2 шт
   💰 Сумма: 3998 ₽
   ⏰ Отгрузка до: завтра в 12:00
   ...

👤 Подними цену на TWS-PRO-001 до 2500 рублей
🤖 [Получает текущую цену: 1999 ₽]
   Текущая цена: 1999 ₽
   Новая цена: 2500 ₽
   Изменение: +25.06%
   
   Подтвердить обновление? (y/N)

👤 Какие товары заканчиваются?
🤖 [Запускает mp-stocks list --low]
   ⚠️ Товары с низкими остатками:
   
   📦 Умная колонка Home Mini (SKU: 789012)
   Остаток: 8 шт — рекомендую пополнить!
   ...
```

### Утренний дайджест (автоматизация)

Создайте скрипт для ежедневного отчёта:

```bash
#!/bin/bash
# examples/morning-digest.sh

echo "📊 Утренний отчёт Ozon ($(date '+%d.%m.%Y'))"
echo ""

echo "📦 Новые заказы:"
mp-orders list | head -20

echo ""
echo "⚠️ Товары с низкими остатками:"
mp-stocks list --low

echo ""
echo "✅ Отчёт готов!"
```

Запускайте через cron или OpenClaw heartbeat.

## 🔧 Режим тестирования (Mock)

Все команды поддерживают флаг `--mock` для тестирования без реального API:

```bash
mp-orders list --mock
mp-prices get TWS-PRO-001 --mock
mp-stocks list --low --mock
```

Mock данные основаны на реальной структуре Ozon API и полезны для:
- Разработки и отладки
- Обучения работе с системой
- Тестирования интеграций

## 🚨 Troubleshooting

### Ошибка: `ERROR: Ozon credentials не настроены`

**Решение:** Запустите `mp-setup` и введите Client ID и API Key.

### Ошибка: `401 - Неверные API credentials`

**Причины:**
- Неправильный Client ID или API Key
- API ключ был удалён или деактивирован

**Решение:**
1. Проверьте credentials в личном кабинете Ozon
2. Создайте новый API ключ
3. Запустите `mp-setup` и введите новые данные

### Ошибка: `403 - Доступ запрещён`

**Причина:** API ключ не имеет нужных прав.

**Решение:**
1. Зайдите в личный кабинет Ozon → Настройки → API ключи
2. Создайте новый ключ с правами **Admin** или **Content + Analytics**
3. Обновите credentials через `mp-setup`

### Ошибка: `429 - Превышен лимит запросов`

**Причина:** Слишком много запросов к API (rate limit).

**Решение:**
- Подождите 60 секунд и повторите
- Система автоматически повторит запрос через некоторое время

### Ошибка: `jq: command not found`

**Решение:** Установите jq:
```bash
# Ubuntu/Debian
sudo apt-get install jq

# macOS
brew install jq
```

## 🔒 Безопасность

- **Credentials хранятся локально** в `~/.openclaw/marketplace/credentials.env`
- **Права доступа 0600** — только владелец может читать файл
- **Не коммитить в git** — `.gitignore` исключает credentials.env
- **Маскировка в логах** — API ключи никогда не логируются в открытом виде

## 📖 Документация API

- [Ozon Seller API Documentation](https://docs.ozon.ru/api/seller/)
- [OpenClaw Documentation](https://docs.openclaw.ai/)

## 🗺️ Roadmap

- [x] **v0.1.0-mvp** — Заказы, цены, остатки (FBS)
- [ ] **v0.2.0** — Финансовые отчёты, аналитика продаж
- [ ] **v0.3.0** — Отзывы и ответы на отзывы
- [ ] **v0.4.0** — FBO (Fulfillment by Ozon) поддержка
- [ ] **v0.5.0** — Wildberries integration
- [ ] **v1.0.0** — Кросс-маркетплейс сравнение и аналитика

## 🤝 Вклад в проект

Contributions are welcome! Пожалуйста:
1. Fork репозиторий
2. Создайте feature branch (`git checkout -b feature/amazing-feature`)
3. Commit изменения (`git commit -m 'Add amazing feature'`)
4. Push в branch (`git push origin feature/amazing-feature`)
5. Создайте Pull Request

## 📄 Лицензия

MIT License — см. [LICENSE](LICENSE)

## 👤 Автор

**Alex** ([@smvlx](https://github.com/smvlx))

- GitHub: https://github.com/smvlx
- Email: alex@openclaw.ai

## 🙏 Благодарности

- [OpenClaw](https://openclaw.ai/) — AI platform
- [Ozon](https://ozon.ru/) — маркетплейс
- Community contributors

---

**Нужна помощь?** Создайте [issue](https://github.com/smvlx/openclaw-marketplace-ru/issues) или напишите в [discussions](https://github.com/smvlx/openclaw-marketplace-ru/discussions).
