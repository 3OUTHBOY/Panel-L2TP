#!/usr/bin/env python3
# آنلاین = IP کلاینتِ کاربر (از لاگ) الان اتصال established به پورت ocserv دارد
import subprocess, os, re, json, time

SESSION_DIR = "/run/l2tp-sessions"
MARKER = "/run/ocserv-tracked"
CACHE = "/run/ocserv-usermap.json"

def ocserv_port():
    try:
        conf = open("/etc/ocserv/ocserv.conf").read()
        m = re.search(r'^\s*tcp-port\s*=\s*(\d+)', conf, re.M)
        if m: return m.group(1)
    except Exception: pass
    return "443"

def load_map():
    try:
        d = json.load(open(CACHE))
        if time.time() - d.get("t", 0) < 3600:
            return d.get("m", {})
    except Exception: pass
    return None

def save_map(m):
    try:
        json.dump({"t": time.time(), "m": m}, open(CACHE, "w"))
    except Exception: pass

def full_map():
    m = {}
    try:
        r = subprocess.run(["journalctl","-u","ocserv","--since","-7 days","--no-pager"],
                           capture_output=True, text=True, timeout=25)
        for line in r.stdout.splitlines():
            mm = re.search(r"worker\[([A-Za-z0-9._-]+)\]:\s+(\d+\.\d+\.\d+\.\d+)", line)
            if mm:
                m[mm.group(2)] = mm.group(1)  # ip -> user
    except Exception: pass
    return m

def user_ip_map():
    m = load_map()
    if m is not None:
        # آپدیت افزایشی: ۲ دقیقه اخیر
        try:
            r = subprocess.run(["journalctl","-u","ocserv","--since","-120 sec","--no-pager"],
                               capture_output=True, text=True, timeout=10)
            for line in r.stdout.splitlines():
                mm = re.search(r"worker\[([A-Za-z0-9._-]+)\]:\s+(\d+\.\d+\.\d+\.\d+)", line)
                if mm:
                    m[mm.group(2)] = mm.group(1)
        except Exception: pass
        save_map(m)
        return m
    m = full_map()
    save_map(m)
    return m

def established_ips(port):
    ips = set()
    try:
        r = subprocess.run(["ss","-Htn","state","established","( sport = :%s )"%port],
                           capture_output=True, text=True, timeout=8)
        for line in r.stdout.splitlines():
            m = re.search(r"(\d+\.\d+\.\d+\.\d+):\d+\s*$", line.strip())
            if m and m.group(1) != "127.0.0.1":
                ips.add(m.group(1))
    except Exception: pass
    return ips

def write_sessions(online):
    os.makedirs(SESSION_DIR, exist_ok=True)
    old = set()
    try:
        old = set(open(MARKER).read().split())
    except Exception: pass
    for name in online:
        try:
            with open(os.path.join(SESSION_DIR, name), "w") as f:
                f.write("99999")
        except Exception: pass
    for name in old - online:
        p = os.path.join(SESSION_DIR, name)
        try:
            if open(p).read().strip() == "99999":
                os.remove(p)
        except Exception: pass
    with open(MARKER, "w") as f:
        f.write("\n".join(online))

if __name__ == "__main__":
    port = ocserv_port()
    m = user_ip_map()
    live = established_ips(port)
    online = set()
    for ip, user in m.items():
        if ip in live:
            online.add(user)
    write_sessions(online)
    print("ocserv online: %d (port %s)" % (len(online), port))
    for u in sorted(online):
        print("  + " + u)
