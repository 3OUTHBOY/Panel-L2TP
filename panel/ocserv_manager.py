#!/usr/bin/env python3
import sqlite3
import subprocess
from datetime import datetime

DB = "/opt/l2tp-panel/users.db"
OCPASSWD = "/etc/ocserv/ocpasswd"

def sync():
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    db = sqlite3.connect(DB)
    db.row_factory = sqlite3.Row
    users = db.execute("SELECT username, password, expires_at, traffic_limit_mb, used_bytes, protocol FROM users").fetchall()
    db.close()

    open("/etc/ocserv/ocpasswd", "w").close()
    for u in users:
        time_ok = u["expires_at"] > now
        used_mb = (u["used_bytes"] or 0) / (1024.0 * 1024.0)
        limit = u["traffic_limit_mb"] or 0
        quota_ok = (limit <= 0) or (used_mb < limit)
        proto_ok = u["protocol"] in ("all", "openconnect")
        if time_ok and quota_ok and proto_ok:
            subprocess.run(
                ["ocpasswd", "-c", OCPASSWD, "-g", "default", u["username"]],
                input=(u["password"] + "\n" + u["password"]).encode(),
                capture_output=True)
    return len(users)

if __name__ == "__main__":
    print("ocserv synced: %d users" % sync())
