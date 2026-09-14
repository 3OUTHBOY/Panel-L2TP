#!/usr/bin/env python3
import subprocess
import os
import re

SESSION_DIR = "/run/l2tp-sessions"

def get_online_users():
    online = set()
    try:
        result = subprocess.run(
            ["journalctl", "-u", "ocserv", "--since", "10 minutes ago", "--no-pager"],
            capture_output=True, text=True, timeout=10
        )
        lines = result.stdout.split("\n")
        # find connect AND disconnect events
        connected = set()
        disconnected = set()
        for line in lines:
            m = re.search(r"worker\[(\w+)\]", line)
            if m:
                username = m.group(1)
                connected.add(username)
            # ocserv logs "user disconnected" when leaving
            if "disconnected" in line or "logout" in line or "removed" in line:
                m2 = re.search(r"worker\[(\w+)\]", line)
                if m2:
                    disconnected.add(m2.group(1))
        online = connected - disconnected
    except Exception:
        pass
    return online

def write_sessions(online):
    if not os.path.exists(SESSION_DIR):
        os.makedirs(SESSION_DIR, exist_ok=True)

    # ocserv marker file approach:
    # track which files WE created (not L2TP's)
    marker = "/run/ocserv-tracked"
    old = set()
    try:
        old = set(open(marker).read().split())
    except Exception:
        pass

    # create sessions for online ocserv users
    for name in online:
        path = os.path.join(SESSION_DIR, name)
        try:
            with open(path, "w") as f:
                f.write("99999")
        except Exception:
            pass

    # remove sessions ONLY for users we previously created
    # AND are now offline (don't touch L2TP sessions!)
    for name in old - online:
        path = os.path.join(SESSION_DIR, name)
        try:
            content = open(path).read().strip()
            if content == "99999":  # our marker value
                os.remove(path)
        except Exception:
            pass

    # save current list
    with open(marker, "w") as f:
        f.write("\n".join(online))

if __name__ == "__main__":
    users = get_online_users()
    print("ocserv online: %d" % len(users))
    for u in sorted(users):
        print("  + " + u)
    write_sessions(users)


