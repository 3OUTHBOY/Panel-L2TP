  os.replace(CHAP_TMP, CHAP_FILE)
    for username in blocked:
        kill_session(username)
    rebuild_dns_rules()

if __name__ == '__main__':
    main()

SYNCPY
chmod 755 ${PANEL_DIR}/sync_users.py

cat > ${PANEL_DIR}/iface_down.py <<'IFACEPY'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Final traffic tally when a PPP interface goes down."""
import os, sqlite3, sys
DB_FILE = '/opt/l2tp-panel/users.db'
IFACE_DIR = '/run/l2tp-ifaces'

def iface_stats(iface):
    total = 0
    for kind in ('rx_bytes', 'tx_bytes'):
        try:
            with open('/sys/class/net/%s/statistics/%s' % (iface, kind)) as fh:
                total += int(fh.read().strip())
        except OSError:
            return None
    return total

def main():
    iface = sys.argv[1] if len(sys.argv) > 1 else ''
    if not iface: return
    path = os.path.join(IFACE_DIR, iface)
    try:
        with open(path) as fh:
            lines = fh.read().split()
        username = lines[0] if lines else ''
        last = int(lines[1]) if len(lines) > 1 else 0
    except Exception:
        return
    current = iface_stats(iface)
    if current is None: current = last
    delta = max(current - last, 0)
    if username and delta > 0:
        try:
            conn = sqlite3.connect(DB_FILE, timeout=10)
            conn.execute('UPDATE users SET used_bytes = used_bytes + ? WHERE username = ?',
                         (delta, username))
            conn.commit(); conn.close()
        except Exception: pass
    try: os.remove(path)
    except OSError: pass

if __name__ == '__main__':
    main()

IFACEPY
chmod 755 ${PANEL_DIR}/iface_down.py

cat > ${PANEL_DIR}/templates/base.html <<'TPL_BASE_HTML'
<!doctype html>
<html lang="{{ lang }}" dir="{{ dir }}" data-theme="dark">
<head>
<meta charset="utf-8">
