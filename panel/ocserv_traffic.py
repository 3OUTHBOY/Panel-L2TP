#!/usr/bin/env python3
import subprocess
import sqlite3
import os
import re

STATE_FILE = "/run/ocserv-last-counter"

def get_ocserv_rx_tx():
    # sum rx+tx of all vpns* interfaces (ocserv creates vpns0, vpns1...)
    total = 0
    for iface in os.listdir("/sys/class/net"):
        if iface.startswith("vpns"):
            for kind in ("rx_bytes", "tx_bytes"):
                try:
                    path = "/sys/class/net/%s/statistics/%s" % (iface, kind)
                    total += int(open(path).read().strip())
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
    d = "/run/l2tp-sessions"
    try:
        return [f for f in os.listdir(d)]
    except Exception:
        return []

def update():
    current = get_ocserv_rx_tx()
    last = get_last()
    delta = current - last
    save_last(current)

    if delta <= 0:
        print("no new traffic")
        return

    users = online_users()
    if not users:
        print("traffic %d bytes but no users online" % delta)
        return

    per_user = delta // len(users)
    db = sqlite3.connect("/opt/l2tp-panel/users.db")
    for u in users:
        db.execute(
            "UPDATE users SET used_bytes = used_bytes + ? WHERE username = ?",
            (per_user, u)
        )
        print("  +%d bytes -> %s" % (per_user, u))
    db.commit()
    db.close()

if __name__ == "__main__":
    update()

