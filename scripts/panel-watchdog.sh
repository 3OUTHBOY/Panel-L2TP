#!/bin/bash
# نگهبان پنل: اگر پنل جواب نداد، ری‌استارتش می‌کند
RESP=$(curl -s -o /dev/null -w '%{http_code}' -m 8 http://127.0.0.1:8000/login)
if [ "$RESP" != "200" ] && [ "$RESP" != "302" ]; then
    logger "PANEL-WATCHDOG: پنل پاسخ نداد (کد: $RESP) — ری‌استارت خودکار"
    systemctl restart l2tp-panel
fi
