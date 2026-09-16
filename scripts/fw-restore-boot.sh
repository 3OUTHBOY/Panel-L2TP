#!/bin/bash
# بازگردانی وضعیت فایروال/بلاکر از config پنل بعد از ریبوت
sleep 10
exec 9>/tmp/fw-apply.lock; flock 9
CFG=/opt/l2tp-panel/config.json
python3 - <<'PY' > /tmp/fw-boot-states
import json
try:
    fw = json.load(open('/opt/l2tp-panel/config.json')).get('firewall', {})
    print('ir', 'on' if fw.get('block_ir') else 'off')
    print('p2p', 'on' if fw.get('block_p2p') else 'off')
    print('ads', 'on' if fw.get('block_ads') else 'off')
except Exception:
    print('ir off'); print('p2p off'); print('ads off')
PY
while read -r what state; do
    /bin/bash /root/firewall-apply.sh "$what" "$state" >/dev/null 2>&1
done < /tmp/fw-boot-states
logger -t FW-RESTORE "FW-RESTORE: firewall states restored after boot"
