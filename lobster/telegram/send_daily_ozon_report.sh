#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$HOME/lobster-marketplace"
TELEGRAM_ENV="$HOME/.openclaw/lobster/telegram.env"
REPORT_SCRIPT="$BASE_DIR/lobster/reports/daily_ozon_report.sh"
THRESHOLD="${1:-15}"

if [[ ! -f "$TELEGRAM_ENV" ]]; then
  echo "ERROR: Telegram env file not found: $TELEGRAM_ENV" >&2
  exit 1
fi

source "$TELEGRAM_ENV"

if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
  echo "ERROR: TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID is empty" >&2
  exit 1
fi

report_text="$("$REPORT_SCRIPT" "$THRESHOLD")"

curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${TELEGRAM_CHAT_ID}" \
  -d "text=${report_text}" \
  -d "disable_web_page_preview=true" >/dev/null

echo "✅ Отчет отправлен в Telegram"
