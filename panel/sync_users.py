#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Sync users to chap-secrets, per-user DNS, traffic tracking, expiry."""
import os, secrets, signal, sqlite3, string, subprocess
from datetime import datetime

BASE = os.path.dirname(os.path.abspath(__file__))
DB_FILE = os.path.join(BASE, 'users.db')
CHAP_FILE = '/etc/ppp/chap-secrets'
CHAP_TMP = CHAP_FILE + '.tmp'
SESS_DIR = '/run/l2tp-sessions'
IFACE_DIR = '/run/l2tp-ifaces'
PEERIP_DIR = '/run/l2tp-peerip'
DNS_MAP_DIR = '/etc/ppp/dns-map'
DNS_CHAIN = 'L2TP_DNS'
DT_FMT = '%Y-%m-%d %H:%M:%S'

def ipt(args):
    try:
        return subprocess.run(['/sbin/iptables'] + args,
                              capture_output=True, timeout=10).returncode == 0
    except Exception:
        return False

def gen_key(length=20):
    alpha = string.ascii_letters + string.digits
    return ''.join(secrets.choice(alpha) for _ in range(length))

def kill_session(username):
    path = os.path.join(SESS_DIR, username)
    try:
        pid = int(open(path).read().strip())
        with open('/proc/%d/comm' % pid) as fh:
            if fh.read().strip().startswith('pppd'):
                os.kill(pid, signal.SIGTERM)
    except Exception: pass
    try: os.remove(path)
    except OSError: pass

def iface_stats(iface):
    total = 0
    for kind in ('rx_bytes', 'tx_bytes'):
        try:
            with open('/sys/class/net/%s/statistics/%s' % (iface, kind)) as fh:
                total += int(fh.read().strip())
        except OSError:
            return None
    return total

def ensure_db(conn):
    conn.execute('''CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        password TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        traffic_limit_mb INTEGER NOT NULL DEFAULT 0,
        used_bytes INTEGER NOT NULL DEFAULT 0,
        dns1 TEXT NOT NULL DEFAULT '',
        dns2 TEXT NOT NULL DEFAULT '',
        dns_key TEXT NOT NULL DEFAULT '')''')
    cols = [r[1] for r in conn.execute('PRAGMA table_info(users)')]
    for col, ddl in (('traffic_limit_mb', 'INTEGER NOT NULL DEFAULT 0'),
                     ('used_bytes', 'INTEGER NOT NULL DEFAULT 0'),
                     ('dns1', "TEXT NOT NULL DEFAULT ''"),
                     ('dns2', "TEXT NOT NULL DEFAULT ''"),
                     ('dns_key', "TEXT NOT NULL DEFAULT ''")):
        if col not in cols:
            conn.execute('ALTER TABLE users ADD COLUMN %s %s' % (col, ddl))
    for (uid,) in conn.execute("SELECT id FROM users WHERE dns_key = ''").fetchall():
        conn.execute('UPDATE users SET dns_key = ? WHERE id = ?', (gen_key(20), uid))
    conn.commit()

def tally_traffic(conn):
    if not os.path.isdir(IFACE_DIR): return
    deltas = {}
    for fname in os.listdir(IFACE_DIR):
        if fname.endswith('.tmp'): continue
        path = os.path.join(IFACE_DIR, fname)
        if not os.path.isfile(path): continue
        try:
            with open(path) as fh:
                lines = fh.read().split()
            username = lines[0] if lines else ''
            last = int(lines[1]) if len(lines) > 1 else 0
        except Exception: continue
        if not username: continue
        current = iface_stats(fname)
        if current is None:
            try: os.remove(path)
            except OSError: pass
            continue
        if current > last:
            deltas[username] = deltas.get(username, 0) + (current - last)
        try:
            with open(path + '.tmp', 'w') as fh:
                fh.write('%s %d\n' % (username, current))
            os.replace(path + '.tmp', path)
        except OSError: pass
    for username, delta in deltas.items():
        conn.execute('UPDATE users SET used_bytes = used_bytes + ? WHERE username = ?',
                     (delta, username))
    conn.commit()

def write_dns_maps(dns_targets):
    os.makedirs(DNS_MAP_DIR, exist_ok=True)
    valid = set()
    for username, target in dns_targets.items():
        path = os.path.join(DNS_MAP_DIR, username)
        tmp = path + '.tmp'
        with open(tmp, 'w') as fh:
            fh.write(target + '\n')
        os.chmod(tmp, 0o600)
        os.replace(tmp, path)
        valid.add(username)
    for fname in os.listdir(DNS_MAP_DIR):
        if fname not in valid:
            try: os.remove(os.path.join(DNS_MAP_DIR, fname))
            except OSError: pass

def rebuild_dns_rules():
    ipt(['-t', 'nat', '-N', DNS_CHAIN])
    if not ipt(['-t', 'nat', '-C', 'PREROUTING', '-j', DNS_CHAIN]):
        ipt(['-t', 'nat', '-A', 'PREROUTING', '-j', DNS_CHAIN])
    ipt(['-t', 'nat', '-F', DNS_CHAIN])
    if not os.path.isdir(PEERIP_DIR): return
    for username in os.listdir(PEERIP_DIR):
        try:
            dns1 = open(os.path.join(DNS_MAP_DIR, username)).read().split()[0].strip()
            peerip = open(os.path.join(PEERIP_DIR, username)).read().strip()
        except Exception: continue
        if dns1 and peerip:
            for proto in ('udp', 'tcp'):
                ipt(['-t', 'nat', '-A', DNS_CHAIN, '-s', peerip, '-p', proto,
                     '--dport', '53', '-j', 'DNAT', '--to-destination', dns1])

def main():
    now = datetime.now().strftime(DT_FMT)
    conn = sqlite3.connect(DB_FILE, timeout=10)
    try:
        ensure_db(conn)
        tally_traffic(conn)
        rows = conn.execute('SELECT username, password, expires_at, traffic_limit_mb, '
                            'used_bytes, dns1, dns2 FROM users').fetchall()
    finally:
        conn.close()
    active, blocked, dns_targets = [], [], {}
    for username, password, expires_at, limit_mb, used, dns1, dns2 in rows:
        time_ok = expires_at > now
        quota_ok = (limit_mb <= 0) or (used < limit_mb * 1024 * 1024)
        if time_ok and quota_ok:
            active.append((username, password))
            target = (dns1 or '').strip() or (dns2 or '').strip()
            if target: dns_targets[username] = target
        else:
            blocked.append(username)
    write_dns_maps(dns_targets)
    with open(CHAP_TMP, 'w') as fh:
        fh.write('# Managed by L2TP Panel - do not edit manually\n')
        for username, password in active:
            fh.write('"%s" l2tpd "%s" *\n' % (username, password))
    os.chmod(CHAP_TMP, 0o600)
    os.replace(CHAP_TMP, CHAP_FILE)
    for username in blocked:
        kill_session(username)
    rebuild_dns_rules()

if __name__ == '__main__':
    main()




