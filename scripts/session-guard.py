#!/usr/bin/env python3
# پاکسازی session های یتیم: فایل‌هایی که pppd شان دیگر زنده نیست
import os

SESS = "/run/l2tp-sessions"

def comm_of(pid):
    try:
        return open("/proc/%d/comm" % pid).read().strip()
    except Exception:
        return None

def main():
    removed = []
    for name in os.listdir(SESS):
        p = os.path.join(SESS, name)
        try:
            val = open(p).read().strip()
        except Exception:
            continue
        if val == "99999":      # فایل‌های ocserv — مال اسکریپت خودش است
            continue
        try:
            pid = int(val)
        except ValueError:
            pid = None
        alive = False
        if pid and comm_of(pid) == "pppd":
            alive = True
        if not alive:
            try:
                os.remove(p)
                removed.append(name)
            except Exception:
                pass
    if removed:
        print("removed stale sessions:", ", ".join(removed))

if __name__ == "__main__":
    main()
