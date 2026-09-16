#!/usr/bin/env python3
import subprocess
import sqlite3
import os
import re
from datetime import datetime

STATE_FILE = "/run/ocserv-last-counter"
DB = "/opt/l2tp-panel/users.db"
LOG_STATE = "/run/ocserv-traffic-log"

def get_ocserv_rx_tx():
    """Sum rx+tx of all vpns* interfaces (ocserv tunnels)"""
    total = 0
    try:
        for iface in os.listdir("/sys/class/net"):
            if iface.startswith("vpns"):
                for kind in ("rx_bytes", "tx_bytes"):
                    try:
                        path = "/sys/class/net/%s/statistics/%s" % (iface, kind)
                        total += int(open(path).read().strip())
                    except Exception:
                        pass
    except Exception:
        pass
    return total

def get_last():
    try:
        return int(open(STATE_FILE).read().strip())
    except Exception:
        return 0

def save_last(v):
    with open(STATE_FILE, "w") as f:
        f.write(str(v))

def online_users():
    """Find ocserv online users from journalctl (recent 10 min)"""
    users = set()
    try:
        result = subprocess.run(
            ["journalctl", "-u", "ocserv", "--since", "10 minutes ago", "--no-pager"],
            capture_output=True, text=True, timeout=10
        )
        connected = set()
        disconnected = set()
        for line in result.stdout.split("\n"):
            m = re.search(r"worker\[(\w+)\]", line)
            if m:
                username = m.group(1)
                connected.add(username)
            if "disconnected" in line or "logout" in line or "removed" in line:
                m2 = re.search(r"worker\[(\w+)\]", line)
                if m2:
                    disconnected.add(m2.group(1))
        users = connected - disconnected
    except Exception:
        pass
    return users

def update():
    current = get_ocserv_rx_tx()
    last = get_last()
    delta = current - last
    save_last(current)

    if delta <= 0:
        return 0

    users = online_users()
    if not users:
        return delta  # nobody online — just reset counter

    # per-user: split by actual usage if possible, else equal
    per_user = delta // len(users)

    db = sqlite3.connect(DB, timeout=15)
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    for u in users:
        db.execute(
            "UPDATE users SET used_bytes = used_bytes + ? WHERE username = ?",
            (per_user, u)
        )
    db.commit()
    db.close()
    return delta

if __name__ == "__main__":
    d = update()
    if d > 0:
        print("ocserv traffic: +%d bytes" % d)
