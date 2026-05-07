#!/usr/bin/env python3
import json
import os
import subprocess
import time
from datetime import date, timedelta
import urllib.parse
import urllib.request
from pathlib import Path


BASE_DIR = Path.home() / "lobster-marketplace"
TELEGRAM_ENV = Path.home() / ".openclaw" / "lobster" / "telegram.env"
BOT_SETTINGS_ENV = BASE_DIR / "lobster" / "config" / "bot_settings.env"
REPORT_SCRIPT = BASE_DIR / "lobster" / "reports" / "daily_ozon_report.sh"
REPORT_LOG_DIR = BASE_DIR / "lobster" / "logs"
STOCK_SCRIPT = BASE_DIR / "lobster" / "reports" / "ozon_stock_report.sh"
SKU_SEARCH_SCRIPT = BASE_DIR / "lobster" / "reports" / "ozon_sku_search.sh"


def load_env_file(path: Path) -> dict:
    env = {}
    if not path.exists():
        raise RuntimeError(f"Telegram env file not found: {path}")

    for raw_line in path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue

        key, value = line.split("=", 1)
        value = value.strip().strip('"').strip("'")
        env[key.strip()] = value

    return env


ENV = load_env_file(TELEGRAM_ENV)
BOT_TOKEN = ENV.get("TELEGRAM_BOT_TOKEN", "")
ALLOWED_CHAT_ID = str(ENV.get("TELEGRAM_CHAT_ID", ""))

if not BOT_TOKEN or not ALLOWED_CHAT_ID:
    raise RuntimeError("TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID is empty")

API_BASE = f"https://api.telegram.org/bot{BOT_TOKEN}"


def api_call(method: str, data: dict | None = None) -> dict:
    url = f"{API_BASE}/{method}"
    encoded = urllib.parse.urlencode(data or {}).encode()

    request = urllib.request.Request(url, data=encoded, method="POST")
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read().decode("utf-8"))


def send_message(chat_id: str, text: str, reply_markup: dict | None = None) -> None:
    payload = {
        "chat_id": chat_id,
        "text": text[:3900],
        "disable_web_page_preview": "true",
    }

    if reply_markup:
        payload["reply_markup"] = json.dumps(reply_markup, ensure_ascii=False)

    api_call("sendMessage", payload)


def answer_callback(callback_query_id: str) -> None:
    api_call("answerCallbackQuery", {"callback_query_id": callback_query_id})


def keyboard(rows: list[list[tuple[str, str]]]) -> dict:
    return {
        "inline_keyboard": [
            [{"text": text, "callback_data": callback_data} for text, callback_data in row]
            for row in rows
        ]
    }


MAIN_MENU = keyboard([
    [("📊 Отчеты", "menu:reports")],
    [("📦 SKU / товары", "menu:sku")],
    [("🏬 Остатки", "menu:stock")],
    [("🚨 Алерты", "menu:alerts")],
    [("⚙️ Настройки", "menu:settings")],
])

REPORTS_MENU = keyboard([
    [("Сегодня", "reports:today"), ("Вчера", "reports:yesterday")],
    [("Неделя", "reports:week")],
    [("⬅️ Назад", "menu:main")],
])

SKU_MENU = keyboard([
    [("Найти SKU", "sku:search")],
    [("Топ продаж", "sku:top")],
    [("Проблемные SKU", "sku:problem")],
    [("⬅️ Назад", "menu:main")],
])

STOCK_MENU = keyboard([
    [("Низкие остатки", "stock:low")],
    [("Закончились", "stock:zero")],
    [("Roast request", "stock:roast_request")],
    [("⬅️ Назад", "menu:main")],
])

ALERTS_MENU = keyboard([
    [("Все активные", "alerts:all")],
    [("Остатки", "alerts:stock")],
    [("Отчеты", "alerts:reports")],
    [("SKU без данных", "alerts:missing_sku")],
    [("⬅️ Назад", "menu:main")],
])

WAITING_FOR_SKU_SEARCH = set()

SETTINGS_MENU = keyboard([
    [("Порог низких остатков", "settings:stock_threshold")],
    [("Время ежедневного отчета", "settings:daily_report_time")],
    [("Магазины", "settings:stores")],
    [("⬅️ Назад", "menu:main")],
])

STOCK_THRESHOLD_MENU = keyboard([
    [("10 шт", "settings:set_stock_threshold:10"), ("15 шт", "settings:set_stock_threshold:15")],
    [("20 шт", "settings:set_stock_threshold:20"), ("30 шт", "settings:set_stock_threshold:30")],
    [("⬅️ Назад", "menu:settings")],
])




def get_bot_setting(key: str, default: str) -> str:
    try:
        settings = load_env_file(BOT_SETTINGS_ENV)
        value = settings.get(key, default)
        return str(value).strip() or default
    except Exception:
        return default


def get_stock_threshold() -> str:
    value = get_bot_setting("STOCK_THRESHOLD", "15")
    return value if value.isdigit() else "15"


def set_bot_setting(key: str, value: str) -> None:
    BOT_SETTINGS_ENV.parent.mkdir(parents=True, exist_ok=True)

    lines = []
    found = False

    if BOT_SETTINGS_ENV.exists():
        lines = BOT_SETTINGS_ENV.read_text().splitlines()

    new_lines = []
    for line in lines:
        stripped = line.strip()

        if not stripped or stripped.startswith("#") or "=" not in line:
            new_lines.append(line)
            continue

        current_key, _ = line.split("=", 1)
        if current_key.strip() == key:
            new_lines.append(f"{key}={value}")
            found = True
        else:
            new_lines.append(line)

    if not found:
        new_lines.append(f"{key}={value}")

    BOT_SETTINGS_ENV.write_text("\n".join(new_lines) + "\n")


def set_stock_threshold(value: str) -> bool:
    if value not in {"5", "10", "15", "20", "30", "50"}:
        return False

    set_bot_setting("STOCK_THRESHOLD", value)
    return True


def main_menu_text() -> str:
    return (
        "🦞 Lobster Bot\n\n"
        "Главное меню MVP-1.\n"
        "Выбери раздел:"
    )


def run_today_report() -> str:
    try:
        result = subprocess.run(
            [str(REPORT_SCRIPT), "15"],
            check=True,
            capture_output=True,
            text=True,
            timeout=90,
        )

        output = result.stdout.strip()

        # daily_ozon_report.sh сейчас пишет служебные строки:
        # 🔄 Получаю цены Ozon...
        # 🔄 Получаю остатки Ozon...
        # 🧮 Формирую отчет...
        # Отчет сохранен...
        # Оставляем полезную часть начиная с заголовка.
        marker = "🦞 Lobster / Ozon / Elevator"
        if marker in output:
            output = output[output.index(marker):]

        saved_marker = "\nОтчет сохранен:"
        if saved_marker in output:
            output = output.split(saved_marker)[0].strip()

        return output or "Отчет сформирован, но текст пустой."

    except subprocess.TimeoutExpired:
        return "ERROR: отчет формировался слишком долго и был остановлен."
    except subprocess.CalledProcessError as error:
        stderr = error.stderr.strip()
        stdout = error.stdout.strip()
        return "ERROR: не удалось сформировать отчет.\n\n" + (stderr or stdout or str(error))
    except Exception as error:
        return f"ERROR: {error}"




def read_saved_daily_report(days_ago: int) -> str:
    report_date = date.today() - timedelta(days=days_ago)
    report_file = REPORT_LOG_DIR / f"daily_ozon_report_{report_date.isoformat()}.txt"

    if not report_file.exists():
        return (
            f"📊 Отчет за {report_date.isoformat()} не найден.\n\n"
            f"Ожидаемый файл:\n{report_file}\n\n"
            "Исторический отчет можно показать только если он был сохранен в logs."
        )

    text = report_file.read_text().strip()

    if not text:
        return f"📊 Отчет за {report_date.isoformat()} найден, но файл пустой."

    marker = "🦞 Lobster / Ozon / Elevator"
    if marker in text:
        text = text[text.index(marker):]

    saved_marker = "\nОтчет сохранен:"
    if saved_marker in text:
        text = text.split(saved_marker)[0].strip()

    return text[:3900]

def run_stock_report(mode: str, threshold: str = "15") -> str:
    try:
        result = subprocess.run(
            [str(STOCK_SCRIPT), mode, threshold],
            check=True,
            capture_output=True,
            text=True,
            timeout=60,
        )
        return result.stdout.strip() or "Данных по остаткам нет."

    except subprocess.TimeoutExpired:
        return "ERROR: отчет по остаткам формировался слишком долго и был остановлен."
    except subprocess.CalledProcessError as error:
        stderr = error.stderr.strip()
        stdout = error.stdout.strip()
        return "ERROR: не удалось сформировать отчет по остаткам.\n\n" + (stderr or stdout or str(error))
    except Exception as error:
        return f"ERROR: {error}"


def run_sku_search(query: str) -> str:
    query = query.strip()

    if not query:
        return "Введите offer_id или product_id для поиска."

    try:
        result = subprocess.run(
            [str(SKU_SEARCH_SCRIPT), query],
            check=True,
            capture_output=True,
            text=True,
            timeout=60,
        )
        return result.stdout.strip() or "SKU не найден."

    except subprocess.TimeoutExpired:
        return "ERROR: поиск SKU выполнялся слишком долго и был остановлен."
    except subprocess.CalledProcessError as error:
        stderr = error.stderr.strip()
        stdout = error.stdout.strip()
        return "ERROR: не удалось выполнить поиск SKU.\n\n" + (stderr or stdout or str(error))
    except Exception as error:
        return f"ERROR: {error}"

def handle_callback(chat_id: str, callback_data: str) -> None:
    if callback_data == "menu:main":
        send_message(chat_id, main_menu_text(), MAIN_MENU)

    elif callback_data == "menu:reports":
        send_message(chat_id, "📊 Отчеты\n\nВыбери период:", REPORTS_MENU)

    elif callback_data == "menu:sku":
        send_message(chat_id, "📦 SKU / товары\n\nРаздел поиска и диагностики товаров.", SKU_MENU)

    elif callback_data == "menu:stock":
        send_message(chat_id, "🏬 Остатки\n\nРаздел контроля остатков и roast request.", STOCK_MENU)

    elif callback_data == "menu:alerts":
        send_message(chat_id, "🚨 Алерты\n\nРаздел активных проблем.", ALERTS_MENU)

    elif callback_data == "menu:settings":
        send_message(chat_id, "⚙️ Настройки\n\nБазовые настройки MVP-1.", SETTINGS_MENU)

    elif callback_data == "reports:today":
        send_message(chat_id, "🔄 Формирую отчет за сегодня...")
        send_message(chat_id, run_today_report(), REPORTS_MENU)

    elif callback_data == "reports:yesterday":
        send_message(chat_id, read_saved_daily_report(1), REPORTS_MENU)

    elif callback_data == "reports:week":
        send_message(
            chat_id,
            "📊 Недельный отчет пока не подключен.\n\nСледующий этап: собрать агрегат за 7 дней.",
            REPORTS_MENU,
        )

    elif callback_data == "sku:search":
        WAITING_FOR_SKU_SEARCH.add(chat_id)
        send_message(
            chat_id,
            "📦 Поиск SKU\n\nВведите offer_id или product_id.\nНапример: FBR или 3549918769",
            SKU_MENU,
        )

    elif callback_data == "sku:top":
        send_message(
            chat_id,
            "📦 Топ продаж пока не подключен.\n\nСледующий этап: подключить данные заказов/продаж.",
            SKU_MENU,
        )

    elif callback_data == "sku:problem":
        send_message(
            chat_id,
            "📦 Проблемные SKU пока частично доступны через раздел 🚨 Алерты и 🏬 Остатки.",
            SKU_MENU,
        )

    elif callback_data == "stock:low":
        send_message(chat_id, "🔄 Получаю низкие остатки...")
        send_message(chat_id, run_stock_report("low", get_stock_threshold()), STOCK_MENU)

    elif callback_data == "stock:zero":
        send_message(chat_id, "🔄 Получаю товары с нулевым остатком...")
        send_message(chat_id, run_stock_report("zero", get_stock_threshold()), STOCK_MENU)

    elif callback_data == "stock:roast_request":
        send_message(chat_id, "🔄 Формирую roast request...")
        send_message(chat_id, run_stock_report("roast", get_stock_threshold()), STOCK_MENU)

    elif callback_data == "alerts:all":
        send_message(chat_id, "🔄 Собираю активные алерты...")
        send_message(chat_id, run_stock_report("alerts", get_stock_threshold()), ALERTS_MENU)

    elif callback_data == "alerts:stock":
        send_message(chat_id, "🔄 Собираю алерты по остаткам...")
        send_message(chat_id, run_stock_report("alerts", get_stock_threshold()), ALERTS_MENU)

    elif callback_data == "alerts:reports":
        send_message(chat_id, run_stock_report("alerts_reports", get_stock_threshold()), ALERTS_MENU)

    elif callback_data == "alerts:missing_sku":
        send_message(chat_id, run_stock_report("missing_sku", get_stock_threshold()), ALERTS_MENU)

    elif callback_data == "settings:stock_threshold":
        send_message(
            chat_id,
            f"🏬 Порог низких остатков\n\nТекущий порог: < {get_stock_threshold()} шт.\n\nВыбери новый порог:",
            STOCK_THRESHOLD_MENU,
        )

    elif callback_data.startswith("settings:set_stock_threshold:"):
        new_threshold = callback_data.split(":")[-1]

        if set_stock_threshold(new_threshold):
            send_message(
                chat_id,
                f"✅ Порог низких остатков обновлен: < {new_threshold} шт.",
                SETTINGS_MENU,
            )
        else:
            send_message(
                chat_id,
                "ERROR: недопустимое значение порога.",
                STOCK_THRESHOLD_MENU,
            )

    elif callback_data == "settings:daily_report_time":
        daily_report_time = get_bot_setting("DAILY_REPORT_TIME", "10:00")
        send_message(
            chat_id,
            f"📊 Время ежедневного отчета\n\nТекущее значение: {daily_report_time}\n\nСейчас cron отдельно отправляет отчет в 10:00.",
            SETTINGS_MENU,
        )

    elif callback_data == "settings:stores":
        send_message(
            chat_id,
            "🏪 Магазины\n\nСейчас подключен контур Ozon / Elevator через текущие Ozon credentials.",
            SETTINGS_MENU,
        )

    else:
        send_message(chat_id, "Неизвестная команда.", MAIN_MENU)


def handle_message(chat_id: str, text: str) -> None:
    normalized = text.strip().lower()

    if normalized in {"/start", "start", "меню", "/menu"}:
        WAITING_FOR_SKU_SEARCH.discard(chat_id)
        send_message(chat_id, main_menu_text(), MAIN_MENU)

    elif chat_id in WAITING_FOR_SKU_SEARCH:
        WAITING_FOR_SKU_SEARCH.discard(chat_id)
        send_message(chat_id, "🔄 Ищу SKU...")
        send_message(chat_id, run_sku_search(text), SKU_MENU)

    elif normalized.startswith("sku "):
        query = text.strip()[4:].strip()
        send_message(chat_id, "🔄 Ищу SKU...")
        send_message(chat_id, run_sku_search(query), SKU_MENU)

    elif "отчет" in normalized and "сегодня" in normalized:
        send_message(chat_id, "🔄 Формирую отчет за сегодня...")
        send_message(chat_id, run_today_report(), REPORTS_MENU)

    elif "отчет" in normalized and "вчера" in normalized:
        send_message(chat_id, read_saved_daily_report(1), REPORTS_MENU)

    else:
        send_message(
            chat_id,
            "Пока я понимаю команды:\n"
            "/start — открыть меню\n"
            "отчет сегодня — сформировать отчет за сегодня\n"
            "sku FBR — найти SKU по offer_id/product_id",
            MAIN_MENU,
        )


def run_bot() -> None:
    print("Lobster Telegram bot started")
    offset = None

    while True:
        try:
            payload = {"timeout": 30}
            if offset is not None:
                payload["offset"] = offset

            response = api_call("getUpdates", payload)

            for update in response.get("result", []):
                offset = update["update_id"] + 1

                if "message" in update:
                    message = update["message"]
                    chat_id = str(message["chat"]["id"])

                    if chat_id != ALLOWED_CHAT_ID:
                        send_message(chat_id, "Access denied.")
                        continue

                    text = message.get("text", "")
                    handle_message(chat_id, text)

                elif "callback_query" in update:
                    callback = update["callback_query"]
                    answer_callback(callback["id"])

                    message = callback.get("message", {})
                    chat_id = str(message.get("chat", {}).get("id", ""))

                    if chat_id != ALLOWED_CHAT_ID:
                        send_message(chat_id, "Access denied.")
                        continue

                    handle_callback(chat_id, callback.get("data", ""))

        except KeyboardInterrupt:
            print("Bot stopped")
            break
        except Exception as error:
            print(f"ERROR: {error}")
            time.sleep(5)


if __name__ == "__main__":
    run_bot()
