#!/bin/bash
# =====================================================================
#   3OUTHBOY PANEL — Multi-Protocol VPN (L2TP+IKEv2+OpenConnect)
#   Ubuntu 20.04/22.04/24.04
#   Interactive:  sudo bash install.sh
#   Unattended:   sudo bash install.sh --user admin --pass X --port 8080 --psk Y
# =====================================================================
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info(){ echo -e "${CYAN}[*]${NC} $1"; }
ok(){   echo -e "${GREEN}[OK]${NC} $1"; }
warn(){ echo -e "${YELLOW}[!]${NC} $1"; }
die(){  echo -e "${RED}[X]${NC} $1"; exit 1; }

[ "$EUID" -eq 0 ] || die "Run with sudo."

PANEL_DIR="/opt/l2tp-panel"

rand_str(){
  local len=${1:-20} out=""
  while [ "${#out}" -lt "$len" ]; do
    out+="$(head -c 64 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9')"
  done
  printf '%s' "${out:0:$len}"
}
sanitize(){ printf '%s' "$1" | LC_ALL=C tr -d '\042\047\134\052\072\073\040\011\012\043'; }

ADMIN_USER="admin"; ADMIN_PASS="$(rand_str 12)"; PANEL_PORT="8080"
PSK="$(rand_str 20)"; ADMIN_IP=""; SET_TZ="y"; ENABLE_UFW="y"
OCSERV_PORT="555"
while [ $# -gt 0 ]; do
  case "$1" in
    --user) ADMIN_USER="$2"; shift 2 ;;
    --pass) ADMIN_PASS="$2"; shift 2 ;;
    --port) PANEL_PORT="$2"; shift 2 ;;
    --psk) PSK="$2"; shift 2 ;;
    --admin-ip) ADMIN_IP="$2"; shift 2 ;;
    --tz) SET_TZ="$2"; shift 2 ;;
    --no-ufw) ENABLE_UFW="n"; shift ;;
    *) shift ;;
  esac
done

if [ -t 0 ]; then
  echo -e "${CYAN}===== 3OUTHBOY PANEL (Multi-Protocol) =====${NC}"
  read -rp "Admin username [${ADMIN_USER}]: " v; ADMIN_USER="${v:-$ADMIN_USER}"
  read -rp "Admin password [${ADMIN_PASS}]: " v; ADMIN_PASS="${v:-$ADMIN_PASS}"
  read -rp "Panel port [${PANEL_PORT}]: " v; PANEL_PORT="${v:-$PANEL_PORT}"
  read -rp "IPSec PSK [${PSK}]: " v; PSK="${v:-$PSK}"
  read -rp "Admin IP (empty=all): " v; ADMIN_IP="${v:-$ADMIN_IP}"
  read -rp "Timezone Asia/Tehran? [Y/n]: " v; SET_TZ="${v:-y}"
  read -rp "Enable UFW? [Y/n]: " v; ENABLE_UFW="${v:-y}"
  read -rp "OpenConnect port [${OCSERV_PORT}]: " v; OCSERV_PORT="${v:-$OCSERV_PORT}"
fi

ADMIN_USER="$(sanitize "$ADMIN_USER" | tr -cd 'A-Za-z0-9_.-')"
ADMIN_PASS="$(sanitize "$ADMIN_PASS")"; PSK="$(sanitize "$PSK")"
ADMIN_USER="${ADMIN_USER:-admin}"; ADMIN_PASS="${ADMIN_PASS:-$(rand_str 12)}"; PSK="${PSK:-$(rand_str 20)}"
[[ "$PANEL_PORT" =~ ^[1-9][0-9]{1,4}$ ]] || PANEL_PORT="8080"

info "Installing packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y -qq
apt-get install -y -qq xl2tpd strongswan strongswan-starter \
  libcharon-extra-plugins libstrongswan-extra-plugins \
  ppp python3 python3-flask gunicorn ufw iptables curl \
  ocserv gnutls-bin net-tools sqlite3 cron >/dev/null 2>&1
ok "Packages installed."

[ "${SET_TZ,,}" != "n" ] && timedatectl set-timezone Asia/Tehran >/dev/null 2>&1 || true

DEF_IF="$(ip -4 route show default | awk '{print $5; exit}')"
[ -n "$DEF_IF" ] || die "No default interface."

info "Detecting IPv4..."
PUB_IP="$(curl -4 -s --max-time 6 https://api.ipify.org || true)"
[ -n "$PUB_IP" ] || PUB_IP="$(curl -4 -s --max-time 6 http://ipv4.icanhazip.com || true)"
[[ "$PUB_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || die "No IPv4 detected."
ok "IPv4: ${PUB_IP}"

grep -q '^precedence ::ffff:0:0/96  100' /etc/gai.conf 2>/dev/null || \
  echo 'precedence ::ffff:0:0/96  100' >> /etc/gai.conf

# ---------- IPSec (L2TP + IKEv2) ----------
info "Configuring IPSec (L2TP + IKEv2)..."
LEFTID="    leftid=${PUB_IP}"
cat > /etc/ipsec.conf <<IPSECEOF
config setup
    uniqueids=no

conn shared
    keyexchange=ikev1
    left=%defaultroute
 ${LEFTID}
    right=%any
    forceencaps=yes
    authby=psk
    pfs=no
    rekey=no
    dpddelay=30
    dpdaction=clear
    ikelifetime=24h
    lifetime=24h
    ike=aes256-sha2_256-modp2048,aes128-sha2_256-modp2048,aes256-sha1-modp2048,aes128-sha1-modp2048,aes256-sha2_256-curve25519,aes128-sha2_256-curve25519,aes256-sha2_256-ecp256,aes128-sha2_256-ecp256,aes256-sha2_256-modp1024,aes128-sha2_256-modp1024,aes256-sha1-modp1024,aes128-sha1-modp1024
    esp=aes256-sha2_256,aes128-sha2_256,aes256-sha2_512,aes256-sha1,aes128-sha1,aes128gcm16,aes256gcm16

conn l2tp-psk
    also=shared
    auto=add
    leftprotoport=17/1701
    rightprotoport=17/%any
    type=transport

conn ikev2-eap
    keyexchange=ikev2
    left=%defaultroute
    leftauth=psk
    leftsubnet=0.0.0.0/0
    right=%any
    rightauth=eap-mschapv2
    rightsourceip=192.168.44.10-192.168.44.250
    fragmentation=yes
    mobike=yes
    auto=add
    ikelifetime=24h
    lifetime=24h
    ike=aes256-sha2_256-modp2048,aes128-sha2_256-modp2048,aes256-sha2_256-curve25519
    esp=aes256-sha2_256,aes128-sha2_256
IPSECEOF

printf '%%any %%any : PSK "%s"\n' "$PSK" > /etc/ipsec.secrets
chmod 600 /etc/ipsec.secrets

cat > /etc/strongswan.d/charon/eap-mschapv2.conf <<'EAPCONF'
eap-mschapv2 {
    load = yes
}
EAPCONF

# ---------- xl2tpd ----------
info "Configuring xl2tpd..."
cat > /etc/xl2tpd/xl2tpd.conf <<'XL2TPDEOF'
[global]
port = 1701

[lns default]
ip range = 192.168.43.10-192.168.43.250
local ip = 192.168.43.1
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
XL2TPDEOF

cat > /etc/ppp/options.xl2tpd <<'PPPOPT'
name l2tpd
ipcp-accept-local
ipcp-accept-remote
ms-dns 8.8.8.8
ms-dns 1.1.1.1
noccp
auth
crtscts
idle 1800
mtu 1410
mru 1410
lock
connect-delay 5000
lcp-echo-interval 30
lcp-echo-failure 5
PPPOPT

# ---------- PPP hooks ----------
mkdir -p /etc/ppp/ip-up.d /etc/ppp/ip-down.d

cat > /etc/ppp/ip-up.d/90l2tp-panel <<'IPUPEOF'
#!/bin/sh
SDIR=/run/l2tp-sessions
PDIR=/run/l2tp-peerip
IDIR=/run/l2tp-ifaces
DMAP=/etc/ppp/dns-map
[ -n "$PEERNAME" ] || exit 0
mkdir -p "$SDIR" "$PDIR" "$IDIR" 2>/dev/null || exit 0
P=$PPID; N=0
while [ -n "$P" ] && [ "$P" != "1" ] && [ "$P" != "0" ] && [ "$N" -lt 6 ]; do
    C=$(ps -o comm= -p "$P" 2>/dev/null)
    case "$C" in
        pppd*) echo "$P" > "$SDIR/$PEERNAME"; break ;;
    esac
    P=$(ps -o ppid= -p "$P" 2>/dev/null | tr -d ' '); N=$((N+1))
done
[ -n "$5" ] && echo "$5" > "$PDIR/$PEERNAME"
[ -n "$1" ] && printf '%s 0\n' "$PEERNAME" > "$IDIR/$1"
if [ -s "$DMAP/$PEERNAME" ] && [ -n "$5" ]; then
    DNS1=$(awk '{print $1}' "$DMAP/$PEERNAME" 2>/dev/null)
    if [ -n "$DNS1" ]; then
        for PROTO in udp tcp; do
            /sbin/iptables -t nat -C L2TP_DNS -s "$5" -p $PROTO --dport 53 -j DNAT --to-destination "$DNS1" 2>/dev/null || \
            /sbin/iptables -t nat -A L2TP_DNS -s "$5" -p $PROTO --dport 53 -j DNAT --to-destination "$DNS1" 2>/dev/null
        done
    fi
fi
exit 0
IPUPEOF
chmod 755 /etc/ppp/ip-up.d/90l2tp-panel

cat > /etc/ppp/ip-down.d/90l2tp-panel <<'IPDOWNEOF'
#!/bin/sh
SDIR=/run/l2tp-sessions
PDIR=/run/l2tp-peerip
IDIR=/run/l2tp-ifaces
DMAP=/etc/ppp/dns-map
if [ -n "$PEERNAME" ]; then
    if [ -s "$DMAP/$PEERNAME" ] && [ -n "$5" ]; then
        DNS1=$(awk '{print $1}' "$DMAP/$PEERNAME" 2>/dev/null)
        if [ -n "$DNS1" ]; then
            for PROTO in udp tcp; do
                /sbin/iptables -t nat -D L2TP_DNS -s "$5" -p $PROTO --dport 53 -j DNAT --to-destination "$DNS1" 2>/dev/null
            done
        done
    fi
    rm -f "$SDIR/$PEERNAME" "$PDIR/$PEERNAME" 2>/dev/null
fi
/usr/bin/python3 /opt/l2tp-panel/iface_down.py "$1" >/dev/null 2>&1
rm -f "$IDIR/$1" 2>/dev/null
exit 0
IPDOWNEOF
chmod 755 /etc/ppp/ip-down.d/90l2tp-panel

mkdir -p /run/l2tp-sessions /run/l2tp-ifaces /run/l2tp-peerip /etc/ppp/dns-map
chmod 700 /run/l2tp-sessions /run/l2tp-ifaces /run/l2tp-peerip /etc/ppp/dns-map

# ---------- NAT ----------
info "Configuring NAT..."
sed -i '/^#\?net.ipv4.ip_forward/d' /etc/sysctl.conf
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -w net.ipv4.ip_forward=1 >/dev/null

cat > /usr/local/sbin/l2tp-nat.sh <<NATEOF
#!/bin/sh
IF="\${DEF_IF:-$(ip -4 route show default | awk '{print \$5; exit}')}"
add(){ /sbin/iptables -t nat -C POSTROUTING -s "\$1" -o "\$IF" -j MASQUERADE 2>/dev/null || /sbin/iptables -t nat -A POSTROUTING -s "\$1" -o "\$IF" -j MASQUERADE; }
del(){ /sbin/iptables -t nat -D POSTROUTING -s "\$1" -o "\$IF" -j MASQUERADE 2>/dev/null || true; }
chain(){
  /sbin/iptables -t nat -N L2TP_DNS 2>/dev/null || true
  /sbin/iptables -t nat -C PREROUTING -j L2TP_DNS 2>/dev/null || /sbin/iptables -t nat -A PREROUTING -j L2TP_DNS
}
mss(){ /sbin/iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || /sbin/iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu; }
case "\$1" in
  start) add 192.168.43.0/24; add 192.168.44.0/24; add 192.168.45.0/24; chain; mss ;;
  stop)  del 192.168.43.0/24; del 192.168.44.0/24; del 192.168.45.0/24; /sbin/iptables -t nat -F L2TP_DNS 2>/dev/null || true ;;
esac
NATEOF
chmod 755 /usr/local/sbin/l2tp-nat.sh

# kernel speed tuning (ocserv)
cat > /etc/sysctl.d/99-vpn-speed.conf <<'SYSEOF'
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
SYSEOF
sysctl -p /etc/sysctl.d/99-vpn-speed.conf >/dev/null 2>&1 || true

cat > /etc/systemd/system/l2tp-nat.service <<'NATSVC'
[Unit]
Description=3OUTHBOY PANEL - NAT
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/l2tp-nat.sh start
ExecStop=/usr/local/sbin/l2tp-nat.sh stop

[Install]
WantedBy=multi-user.target
NATSVC

# ---------- ocserv (OpenConnect/AnyConnect) ----------
info "Configuring OpenConnect (AnyConnect)..."
mkdir -p /etc/ocserv/certs
cd /etc/ocserv
if [ ! -f certs/server-key.pem ]; then
  printf 'cn = 3OUTHBOY CA\n' > ca.tmpl
  certtool --generate-privkey --outfile certs/ca-key.pem 2>/dev/null
  certtool --generate-self-signed --load-privkey certs/ca-key.pem --template ca.tmpl --outfile certs/ca-cert.pem 2>/dev/null
  printf 'cn = %s\n' "$PUB_IP" > server.tmpl
  certtool --generate-privkey --outfile certs/server-key.pem 2>/dev/null
  certtool --generate-certificate --load-privkey certs/server-key.pem --load-ca-certificate certs/ca-cert.pem --load-ca-privkey certs/ca-key.pem --template server.tmpl --outfile certs/server-cert.pem 2>/dev/null
  ok "certs generated"
fi

cat > /etc/ocserv/ocserv.conf <<OCCONF
auth = "plain[/etc/ocserv/ocpasswd]"
tcp-port = ${OCSERV_PORT}
udp-port = ${OCSERV_PORT}
run-as-user = nobody
run-as-group = nogroup
device = vpns
ipv4-network = 192.168.45.0/24
dns = 8.8.8.8
server-cert = /etc/ocserv/certs/server-cert.pem
server-key = /etc/ocserv/certs/server-key.pem
ca-cert = /etc/ocserv/certs/ca-cert.pem
max-clients = 16
max-same-clients = 2
keepalive = 30
compression = no
mtu = 1420
try-mtu-discovery = true
log-level = 1
dpd = 60
socket-file = /var/run/ocserv.socket
mobile-dpd = 1800
route = 0.0.0.0/0.0.0.0/0
OCCONF

touch /etc/ocserv/ocpasswd

# ---------- panel config ----------
info "Installing panel..."
mkdir -p "${PANEL_DIR}/templates"

cat > "${PANEL_DIR}/config.json" <<CONFJSON
{
  "admin_user": "${ADMIN_USER}",
  "admin_pass": "${ADMIN_PASS}",
  "psk": "${PSK}",
  "server_ip": "${PUB_IP}",
  "secret_key": "$(rand_str 32)"
}
CONFJSON
chmod 600 "${PANEL_DIR}/config.json"

cat > "${PANEL_DIR}/panel.py" <<'ZQ_panel_py'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""3OUTHBOY PANEL (fa/en) — expiry, quotas, DNS, keys, restart, self-update."""
import json, os, re, secrets, shlex, socket, sqlite3, string, subprocess, tempfile, threading, time
import urllib.request
from datetime import datetime, timedelta
from functools import wraps
from urllib.parse import urlparse
from flask import Flask, abort, flash, redirect, render_template, request, session, url_for

BASE = os.path.dirname(os.path.abspath(__file__))
DB_FILE = os.path.join(BASE, 'users.db')
SESS_DIR = '/run/l2tp-sessions'
DT_FMT = '%Y-%m-%d %H:%M:%S'
USERNAME_RE = re.compile(r'^[A-Za-z0-9_.-]{3,32}$')
KEY_RE = re.compile(r'^[A-Za-z0-9]{8,32}$')
IPV4_RE = re.compile(r'^(\d{1,3}\.){3}\d{1,3}$')
BAD_PW_CHARS = set(' \t\n\r"\'\\*:;#')
DEFAULT_LANG = 'fa'
PANEL_VERSION = '3.0.0'
UPDATE_URL = 'https://raw.githubusercontent.com/3OUTHBOY/Panel-L2TP/main/install.sh'
UPDATE_LOG = '/var/log/l2tp-panel-update.log'

with open(os.path.join(BASE, 'config.json'), encoding='utf-8') as fh:
    CFG = json.load(fh)

TRANSLATIONS = {
 'fa': {
  'brand':'پنل 3OUTHBOY','header_title':'پنل 3OUTHBOY','login_title':'پنل 3OUTHBOY',
  'username':'نام کاربری','password':'رمز عبور','login_btn':'ورود',
  'err_credentials':'نام کاربری یا رمز عبور اشتباه است.',
  'err_locked':'تلاش‌های ناموفق زیاد بوده؛ ۵ دقیقه بعد دوباره امتحان کنید.',
  'server_address':'آدرس سرور','psk_label':'کلید مشترک (PSK)','active_users':'کاربران فعال',
  'online_sessions':'نشست‌های متصل','services_status':'وضعیت سرویس‌ها','of_word':'از',
  'add_user_title':'افزودن کاربر جدید','password_auto':'رمز عبور (خالی = خودکار)',
  'auto_placeholder':'خودکار','days_label':'مدت اعتبار (روز)',
  'exact_expiry':'تاریخ و ساعت دقیق انقضا (اختیاری)','add_btn':'افزودن کاربر',
  'exact_note':'اگر تاریخ دقیق را انتخاب کنید فیلد «روز» نادیده گرفته می‌شود.',
  'traffic_label':'محدودیت حجم (GB)','traffic_ph':'نامحدود',
  'dns1_label':'DNS اول (خالی = پیش‌فرض)','dns2_label':'DNS دوم (خالی = پیش‌فرض)',
  'users_title':'کاربران','th_username':'نام کاربری','th_password':'رمز عبور','th_expiry':'انقضا',
  'th_remaining':'باقی‌مانده','th_traffic':'حجم مصرفی','th_dns':'DNS اختصاصی','th_key':'کد کاربر',
  'default_dns':'پیش‌فرض','th_status':'وضعیت','th_actions':'عملیات','badge_active':'فعال',
  'badge_soon':'در حال اتمام','badge_expired':'منقضی','badge_quota':'حجم تمام شد',
  'renew_btn':'تمدید','online_tip':'آنلاین','no_users':'هنوز کاربری اضافه نشده است.',
  'delete_confirm':'این کاربر حذف شود؟','edit_title':'ویرایش کاربر',
  'new_password':'رمز عبور جدید (خالی = بدون تغییر)',
  'new_expiry':'تاریخ و ساعت انقضای جدید (خالی = بدون تغییر)',
  'new_traffic':'محدودیت حجم جدید به GB (خالی = بدون تغییر، ۰ = نامحدود)',
  'new_dns1':'DNS اول (خالی = حذف DNS اختصاصی)','new_dns2':'DNS دوم (خالی = حذف DNS اختصاصی)',
  'new_key':'کد کاربر (خالی = بدون تغییر)','cancel':'انصراف','save':'ذخیره',
  'sync_btn':'🔄 همگام‌سازی','restart_vpn_btn':'🚀 ریستارت VPN','restart_panel_btn':'♻️ ریستارت پنل',
  'restart_vpn_confirm':'سرویس‌های VPN ریستارت شوند؟ کاربران متصل موقتاً قطع می‌شوند.',
  'restart_panel_confirm':'پنل ریستارت شود؟ چند ثانیه طول می‌کشد.',
  'vpn_restarted':'همه سرویس‌های VPN با موفقیت ریستارت شدند.',
  'vpn_restart_failed':'بعضی سرویس‌ها ریستارت نشدند! با journalctl بررسی کنید.',
  'panel_restarting':'پنل در حال ریستارت است...',
  'restarting_msg':'چند ثانیه صبر کنید؛ صفحه به صورت خودکار بارگذاری می‌شود.',
  'update_btn':'🔄 آپدیت پنل','updating_title':'در حال آپدیت پنل...',
  'updating_msg':'نسخه جدید از گیت‌هاب در حال دانلود و نصب است. چند دقیقه صبر کنید؛ صفحه خودکار بازمی‌گردد و باید دوباره وارد شوید.',
  'update_confirm':'پنل از گیت‌هاب آپدیت شود؟ چند دقیقه طول می‌کشد و بعدش باید دوباره لاگین کنید.',
  'update_failed':'آپدیت ناموفق بود! اتصال سرور به گیت‌هاب را بررسی کنید.',
  'tab_dashboard':'داشبورد','tab_users':'کاربران','tab_settings':'تنظیمات','total_traffic':'مصرف کل کاربران','sum_of_quotas':'مجموع سهم کاربران محدود','settings_account':'حساب ادمین','settings_account_desc':'نام کاربری و رمز عبور ورود به پنل','cur_password':'رمز فعلی','new_username':'نام کاربری جدید','new_password':'رمز عبور جدید','new_password2':'تکرار رمز عبور جدید','save_btn':'ذخیره تغییرات','creds_note':'بعد از ذخیره، از پنل خارج می‌شوید و باید با اطلاعات جدید وارد شوید.','wrong_cur_password':'رمز فعلی اشتباه است.','password_mismatch':'رمزهای جدید یکسان نیستند.','invalid_password_short':'رمز جدید باید حداقل ۶ کاراکتر باشد.','relogin_note':'اعتبارنامه‌ها تغییر کرد؛ لطفاً با اطلاعات جدید وارد شوید.','settings_vpn':'تنظیمات VPN','change_psk':'تغییر کلید PSK','change_psk_warn':'هشدار: با تغییر PSK همه کاربران باید PSK جدید را در دستگاه خود وارد کنند و کاربران متصل موقتاً قطع می‌شوند.','new_psk':'PSK جدید (حداقل ۸ کاراکتر)','invalid_psk':'PSK نامعتبر است (حداقل ۸ کاراکتر، بدون فاصله).','psk_saved':'PSK جدید ذخیره شد و سرویس IPSec ریستارت شد.','default_dns_title':'DNS پیش‌فرض سرور (کاربران بدون DNS اختصاصی)','dns_saved':'DNS پیش‌فرض ذخیره شد و سرویس L2TP ریستارت شد.','settings_panel':'تنظیمات پنل','cur_port':'پورت فعلی','port_label':'پورت جدید پنل','port_warn':'بعد از تغییر پورت، چند ثانیه بعد به آدرس جدید منتقل می‌شوید. پورت جدید به‌صورت خودکار در فایروال باز می‌شود.','invalid_port':'پورت نامعتبر است (عدد بین ۱۰۲۴ تا ۶۵۵۳۵).','settings_data':'داده‌ها و بکاپ','backup_btn':'📥 دانلود فایل بکاپ','backup_note':'شامل همه کاربران، حجم‌ها، تاریخ انقضا و تنظیمات پنل. در جای امن نگه دارید.','chart_title':'مصرف ۷ روز اخیر','top_users':'مصرف‌کننده‌های برتر','expired_count':'کاربران منقضی','capacity':'ظرفیت سیستم','slots_used':'اسلات IP استفاده‌شده','today':'امروز','no_chart_data':'هنوز داده‌ای ثبت نشده — از فردا نمودار پر می‌شود.','restore_title':'بازگردانی بکاپ','restore_btn':'📤 بازگردانی از بکاپ','restore_note':'فایل بکاپ (zip) را انتخاب کنید — همه کاربران و تنظیمات جایگزین وضعیت فعلی می‌شوند. قبل از بازگردانی، از وضعیت فعلی بکاپ خودکار گرفته می‌شود.','restore_confirm':'بازگردانی انجام شود؟ داده‌های فعلی کاربران جایگزین می‌شوند!','restore_no_file':'فایلی انتخاب نشده است.','restore_bad_file':'فایل بکاپ معتبر نیست.','restore_done':'بکاپ با موفقیت بازگردانی شد.','logout_btn':'خروج','copy_tip':'کپی','show_tip':'نمایش',
  'reset_traffic_tip':'صفر کردن حجم مصرفی','regen_key_tip':'تولید کد جدید',
  'status_link_tip':'صفحه وضعیت کاربر','theme_tip':'حالت روشن / تاریک',
  'invalid_username':'نام کاربری نامعتبر است (۳ تا ۳۲ کاراکتر لاتین/عدد).',
  'bad_pw_chars':'رمز عبور نباید شامل فاصله یا کاراکترهای " \' \\ * : ; # باشد.',
  'bad_pw_chars_short':'رمز عبور دارای کاراکترهای غیرمجاز است.',
  'invalid_expiry':'قالب تاریخ/ساعت انقضا نامعتبر است.',
  'invalid_days':'تعداد روز باید بین ۱ تا ۳۶۵۰ باشد.','invalid_days_short':'تعداد روز نامعتبر است.',
  'invalid_date':'قالب تاریخ نامعتبر است.','invalid_traffic':'محدودیت حجم نامعتبر است.',
  'invalid_dns':'آدرس DNS نامعتبر است (باید IPv4 باشد).',
  'invalid_key':'کد کاربر نامعتبر است (۸ تا ۳۲ کاراکتر لاتین/عدد).',
  'user_exists':'نام کاربری «{username}» قبلاً ثبت شده است.',
  'user_added':'کاربر «{username}» اضافه شد. رمز عبور: {password}',
  'user_not_found':'کاربر پیدا نشد.','renewed':'اعتبار کاربر تمدید شد.',
  'nothing_changed':'چیزی برای تغییر وارد نشده است.','changes_saved':'تغییرات ذخیره شد.',
  'user_deleted':'کاربر حذف شد.','sync_done':'همگام‌سازی انجام شد.',
  'traffic_reset':'شمارنده حجم کاربر صفر شد.',
  'key_regenerated':'کد جدید تولید شد (لینک قبلی دیگر کار نمی‌کند).',
  'invalid_request':'درخواست نامعتبر رد شد.','status_title':'وضعیت اشتراک VPN',
  'st_server':'آدرس سرور','st_type':'نوع اتصال','st_psk':'کلید مشترک (PSK)',
  'st_dns':'DNS','st_dns_default':'پیش‌فرض سرور','st_expiry':'تاریخ انقضا',
  'st_remaining':'زمان باقی‌مانده','st_traffic':'حجم مصرفی',
 },
 'en': {
  'brand':'PANEL 3OUTHBOY','header_title':'3OUTHBOY Panel','login_title':'PANEL 3OUTHBOY',
  'username':'Username','password':'Password','login_btn':'Sign in',
  'err_credentials':'Invalid username or password.',
  'err_locked':'Too many failed attempts; try again in 5 minutes.',
  'server_address':'Server address','psk_label':'Pre-shared key (PSK)','active_users':'Active users',
  'online_sessions':'Connected sessions','services_status':'Services','of_word':'of',
  'add_user_title':'Add new user','password_auto':'Password (blank = auto-generate)',
  'auto_placeholder':'Auto','days_label':'Validity (days)',
  'exact_expiry':'Exact expiry date & time (optional)','add_btn':'Add user',
  'exact_note':'If you pick an exact date, the days field is ignored.',
  'traffic_label':'Traffic limit (GB)','traffic_ph':'Unlimited',
  'dns1_label':'Primary DNS (blank = default)','dns2_label':'Secondary DNS (blank = default)',
  'users_title':'Users','th_username':'Username','th_password':'Password','th_expiry':'Expires',
  'th_remaining':'Remaining','th_traffic':'Traffic used','th_dns':'Custom DNS','th_key':'User key',
  'default_dns':'Default','th_status':'Status','th_actions':'Actions','badge_active':'Active',
  'badge_soon':'Expiring soon','badge_expired':'Expired','badge_quota':'Quota exceeded',
  'renew_btn':'Renew','online_tip':'online','no_users':'No users yet.',
  'delete_confirm':'Delete this user?','edit_title':'Edit user',
  'new_password':'New password (blank = unchanged)',
  'new_expiry':'New expiry date & time (blank = unchanged)',
  'new_traffic':'New traffic limit in GB (blank = unchanged, 0 = unlimited)',
  'new_dns1':'Primary DNS (blank = remove custom DNS)','new_dns2':'Secondary DNS (blank = remove custom DNS)',
  'new_key':'User key (blank = unchanged)','cancel':'Cancel','save':'Save',
  'sync_btn':'🔄 Sync','restart_vpn_btn':'🚀 Restart VPN','restart_panel_btn':'♻️ Restart Panel',
  'restart_vpn_confirm':'Restart VPN services? Connected users will be temporarily disconnected.',
  'restart_panel_confirm':'Restart the panel? Takes a few seconds.',
  'vpn_restarted':'All VPN services restarted successfully.',
  'vpn_restart_failed':'Some services failed to restart! Check journalctl.',
  'panel_restarting':'Panel is restarting...',
  'restarting_msg':'Please wait; this page will reload automatically.',
  'update_btn':'🔄 Update Panel','updating_title':'Updating panel...',
  'updating_msg':'Downloading and installing the new version from GitHub. This takes a few minutes; the page will return automatically and you will need to log in again.',
  'update_confirm':'Update the panel from GitHub? Takes a few minutes and you will need to log in again.',
  'update_failed':'Update failed! Check server connectivity to GitHub.',
  'tab_dashboard':'Dashboard','tab_users':'Users','tab_settings':'Settings','total_traffic':'Total traffic (all users)','sum_of_quotas':'Sum of user quotas','settings_account':'Admin Account','settings_account_desc':'Panel login username and password','cur_password':'Current password','new_username':'New username','new_password':'New password','new_password2':'Repeat new password','save_btn':'Save changes','creds_note':'After saving you will be logged out and must sign in with the new credentials.','wrong_cur_password':'Current password is wrong.','password_mismatch':'New passwords do not match.','invalid_password_short':'New password must be at least 6 characters.','relogin_note':'Credentials changed — please sign in with the new ones.','settings_vpn':'VPN Settings','change_psk':'Change PSK','change_psk_warn':'Warning: after changing the PSK, all users must enter the new PSK on their devices; connected users will be disconnected briefly.','new_psk':'New PSK (min 8 chars)','invalid_psk':'Invalid PSK (min 8 chars, no spaces).','psk_saved':'New PSK saved and IPSec service restarted.','default_dns_title':'Server default DNS (users without custom DNS)','dns_saved':'Default DNS saved and L2TP service restarted.','settings_panel':'Panel Settings','cur_port':'Current port','port_label':'New panel port','port_warn':'After changing the port you will be redirected to the new address in a few seconds. The new port is opened in the firewall automatically.','invalid_port':'Invalid port (number between 1024 and 65535).','settings_data':'Data & Backup','backup_btn':'📥 Download backup','backup_note':'Contains all users, quotas, expiry dates and panel settings. Keep it somewhere safe.','chart_title':'Traffic — last 7 days','top_users':'Top consumers','expired_count':'Expired users','capacity':'System capacity','slots_used':'IP slots used','today':'Today','no_chart_data':'No data yet — the chart fills up day by day.','restore_title':'Restore Backup','restore_btn':'📤 Restore from backup','restore_note':'Select a backup zip — all users and settings replace the current state. A safety backup of the current state is taken automatically before restoring.','restore_confirm':'Restore now? Current user data will be replaced!','restore_no_file':'No file selected.','restore_bad_file':'Invalid backup file.','restore_done':'Backup restored successfully.','logout_btn':'Logout','copy_tip':'Copy','show_tip':'Show',
  'reset_traffic_tip':'Reset traffic counter','regen_key_tip':'Regenerate key',
  'status_link_tip':'User status page','theme_tip':'Toggle light / dark mode',
  'invalid_username':'Invalid username (3-32 chars).',
  'bad_pw_chars':'Password must not contain spaces or " \' \\ * : ; #.',
  'bad_pw_chars_short':'Password contains invalid characters.',
  'invalid_expiry':'Invalid expiry date/time format.',
  'invalid_days':'Days must be between 1 and 3650.','invalid_days_short':'Invalid number of days.',
  'invalid_date':'Invalid date format.','invalid_traffic':'Invalid traffic limit.',
  'invalid_dns':'Invalid DNS address (must be IPv4).',
  'invalid_key':'Invalid user key (8-32 alphanumeric characters).',
  'user_exists':'Username "{username}" already exists.',
  'user_added':'User "{username}" added. Password: {password}',
  'user_not_found':'User not found.','renewed':'User renewed successfully.',
  'nothing_changed':'Nothing to change.','changes_saved':'Changes saved.',
  'user_deleted':'User deleted.','sync_done':'Sync completed.',
  'traffic_reset':'Traffic counter reset.',
  'key_regenerated':'New key generated (old link no longer works).',
  'invalid_request':'Invalid request rejected.','status_title':'VPN Subscription Status',
  'st_server':'Server address','st_type':'Connection type','st_psk':'Pre-shared key (PSK)',
  'st_dns':'DNS','st_dns_default':'Server default','st_expiry':'Expiry date',
  'st_remaining':'Time remaining','st_traffic':'Traffic used',
 },
}

app = Flask(__name__)
app.secret_key = CFG['secret_key']
app.permanent_session_lifetime = timedelta(hours=12)
app.config.update(SESSION_COOKIE_HTTPONLY=True, SESSION_COOKIE_SAMESITE='Lax')

_attempts = {}
_lock = threading.Lock()

def get_lang():
    # cookie همیشه تازه‌ترین انتخاب کاربره (JS سوییچ زبان همون لحظه ست می‌کنه)
    cookie_lang = request.cookies.get('l2tp_lang')
    if cookie_lang in ('fa', 'en'):
        if session.get('lang') != cookie_lang:
            session['lang'] = cookie_lang
        return cookie_lang
    # fallback: session → default
    return session.get('lang', DEFAULT_LANG)


def T(key, **kwargs):
    text = TRANSLATIONS.get(get_lang(), TRANSLATIONS[DEFAULT_LANG]).get(key) \
        or TRANSLATIONS['en'].get(key, key)
    return text.format(**kwargs) if kwargs else text

def fmt_remaining(secs, lang):
    d, h, m = int(secs // 86400), int((secs % 86400) // 3600), int((secs % 3600) // 60)
    if lang == 'en':
        if d > 0: return '{}d {}h'.format(d, h)
        if h > 0: return '{}h {}m'.format(h, m)
        return '{}m'.format(max(m, 1))
    if d > 0: return '{}d {}h'.format(d, h)
    if h > 0: return '{}h {}m'.format(h, m)
    return '{}m'.format(max(m, 1))

def fmt_gb(nbytes):
    gb = nbytes / (1024.0 ** 3)
    if gb >= 100: return '{:.0f}'.format(gb)
    if gb >= 10: return '{:.1f}'.format(gb)
    return '{:.2f}'.format(gb)

def fmt_traffic(nbytes):
    gb = nbytes / (1024.0 ** 3)
    if gb >= 1: return fmt_gb(nbytes) + ' GB'
    mb = nbytes / (1024.0 ** 2)
    if mb >= 1: return '{:.0f} MB'.format(mb)
    return '{} KB'.format(int(nbytes / 1024.0))

def parse_traffic_gb(raw):
    raw = raw.strip()
    if not raw: return 0
    try: gb = float(raw.replace(',', '.'))
    except ValueError: return None
    if gb < 0 or gb > 100000: return None
    return int(round(gb * 1024))

def gen_key(length=20):
    alpha = string.ascii_letters + string.digits
    return ''.join(secrets.choice(alpha) for _ in range(length))

@app.context_processor
def inject_i18n():
    lang = get_lang()
    return {'t': TRANSLATIONS.get(lang, TRANSLATIONS[DEFAULT_LANG]),
            'lang': lang, 'dir': 'rtl' if lang == 'fa' else 'ltr',
            'panel_version': PANEL_VERSION}

def get_db():
    conn = sqlite3.connect(DB_FILE, timeout=10)
    conn.row_factory = sqlite3.Row
    return conn

def db_execute(query, params=()):
    conn = get_db()
    try:
        conn.execute(query, params); conn.commit()
    finally:
        conn.close()

def init_db():
    conn = get_db()
    try:
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
            dns_key TEXT NOT NULL DEFAULT '',
            telegram TEXT NOT NULL DEFAULT '',
            protocol TEXT NOT NULL DEFAULT 'all',
            max_devices INTEGER NOT NULL DEFAULT 0,
            note TEXT NOT NULL DEFAULT '')''')
        cols = [r[1] for r in conn.execute('PRAGMA table_info(users)')]
        for col, ddl in (('telegram', "TEXT NOT NULL DEFAULT ''"),
                         ('protocol', "TEXT NOT NULL DEFAULT 'all'"),
                         ('max_devices', 'INTEGER NOT NULL DEFAULT 0'),
                         ('note', "TEXT NOT NULL DEFAULT ''")):
            if col not in cols:
                conn.execute('ALTER TABLE users ADD COLUMN %s %s' % (col, ddl))
        conn.commit()
    finally:
        conn.close()

def run_sync():
    try:
        subprocess.run(['/usr/bin/python3', os.path.join(BASE, 'sync_users.py')],
                       capture_output=True, timeout=30)
    except Exception: pass

def kill_session(username):
    path = os.path.join(SESS_DIR, username)
    try:
        pid = int(open(path).read().strip())
        with open('/proc/%d/comm' % pid) as fh:
            if fh.read().strip().startswith('pppd'):
                os.kill(pid, 15)
    except Exception: pass
    try: os.remove(path)
    except OSError: pass

def service_active(name):
    try:
        return subprocess.run(['systemctl', 'is-active', name],
                              capture_output=True, text=True,
                              timeout=5).stdout.strip() == 'active'
    except Exception: return False

def restart_service(name):
    try:
        return subprocess.run(['systemctl', 'restart', name],
                              capture_output=True, timeout=60).returncode == 0
    except Exception: return False

def server_ip():
    ip = CFG.get('server_ip') or ''
    if IPV4_RE.match(ip): return ip
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('8.8.8.8', 80)); return s.getsockname()[0]
    except Exception: return '127.0.0.1'
    finally: s.close()

SERVER_IP = server_ip()

def gen_password(length=12):
    alpha = string.ascii_letters + string.digits
    return ''.join(secrets.choice(alpha) for _ in range(length))

def parse_dt(v):
    for f in ('%Y-%m-%dT%H:%M', '%Y-%m-%dT%H:%M:%S'):
        try: return datetime.strptime(v, f)
        except ValueError: continue
    return None

def user_row_to_dict(row):
    now = datetime.now(); lang = get_lang()
    exp = datetime.strptime(row['expires_at'], DT_FMT)
    secs = (exp - now).total_seconds()
    expired = secs <= 0
    limit_mb = row['traffic_limit_mb'] or 0
    used = row['used_bytes'] or 0
    limit_bytes = limit_mb * 1024 * 1024
    quota_exceeded = limit_mb > 0 and used >= limit_bytes
    traffic_pct = min(int(used * 100 / limit_bytes), 100) if limit_bytes > 0 else 0
    traffic = ('{} / {}'.format(fmt_traffic(used), fmt_traffic(limit_bytes))
               if limit_mb > 0 else '{} / ∞'.format(fmt_traffic(used)))
    remaining = fmt_remaining(secs, session.get('lang', 'fa')) if not expired and not quota_exceeded else '—'
    return {'id': row['id'], 'username': row['username'], 'password': row['password'],
            'expires': row['expires_at'],
            'expires_input': row['expires_at'][:16].replace(' ', 'T'),
            'remaining': remaining, 'expired': expired,
            'soon': (not expired) and secs < 3 * 86400,
            'traffic': traffic, 'quota_exceeded': quota_exceeded,
            'limit_gb': round(limit_mb / 1024.0, 2), 'traffic_pct': traffic_pct,
            'dns1': row['dns1'] or '', 'dns2': row['dns2'] or '',
            'key': row['dns_key'] or '',
            'telegram': row['telegram'] or '',
            'protocol': row['protocol'] or 'all',
            'max_devices': row['max_devices'] or 0,
            'note': row['note'] or ''}

def login_required(view):
    @wraps(view)
    def w(*a, **k):
        if not session.get('admin'):
            return redirect(url_for('login'))
        return view(*a, **k)
    return w

@app.before_request
def csrf_protect():
    if request.method != 'POST': return None
    src = request.headers.get('Origin') or request.headers.get('Referer')
    if not src: return None
    if urlparse(src).netloc and urlparse(src).netloc != request.host:
        flash_i18n("درخواست نامعتبر رد شد.", "Invalid request rejected.")
        return redirect(url_for('index') if session.get('admin') else url_for('login'))
    return None


# دو زبانه: پیام با کلید — JS سمت کلاینت متن درست رو انتخاب می‌کنه
def flash_i18n(fa_text, en_text):
    session['flash_msg'] = {'fa': fa_text, 'en': en_text}
    flash('FA:' + fa_text)



def flash_bi(fa, en):
    flash('FA:' + str(fa) + '|EN:' + str(en))



def flash_err(fa, en):
    flash('ERR_FA:' + str(fa) + '|EN:' + str(en))


@app.route('/lang/<string:code>')
def set_lang(code):
    if code in TRANSLATIONS:
        session['lang'] = code
    resp = redirect(request.referrer or url_for('index'))
    resp.set_cookie('l2tp_lang', code, max_age=365*24*3600)
    return resp
@app.route('/login', methods=['GET', 'POST'])
def login():
    error = None
    if request.method == 'POST':
        # زبان انتخاب‌شده روی صفحه لاگین — قبل از هرچیز اعمال شه
        _lg = request.form.get('login_lang', '')
        if _lg in ('fa', 'en'):
            session['lang'] = _lg
        # کوکی هم چک شه (اگه JS ست کرده باشه)
        _ck = request.cookies.get('l2tp_lang', '')
        if _ck in ('fa', 'en') and not _lg:
            session['lang'] = _ck
        username = request.form.get('username', '')
        password = request.form.get('password', '')
        ip = request.remote_addr or '?'
        now = time.time(); locked = False
        with _lock:
            recent = [t for t in _attempts.get(ip, []) if now - t < 300]
            if len(recent) >= 10:
                locked = True
            elif username == CFG['admin_user'] and password == CFG['admin_pass']:
                _attempts.pop(ip, None)
                session.permanent = True
                session['admin'] = True
                return redirect(url_for('index'))
            else:
                recent.append(now); _attempts[ip] = recent
        error = T('err_locked') if locked else T('err_credentials')
    return render_template('login.html', error=error, relogin=request.args.get('relogin'))

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))


def _record_daily_stats():
    # Record today's total usage snapshot (idempotent per day).
    try:
        conn = get_db()
        conn.execute("CREATE TABLE IF NOT EXISTS daily_stats ("
                     "day TEXT PRIMARY KEY, "
                     "total_bytes INTEGER NOT NULL DEFAULT 0)")
        today = datetime.now().strftime('%Y-%m-%d')
        row = conn.execute('SELECT COALESCE(SUM(used_bytes),0) FROM users').fetchone()
        total = row[0] if row else 0
        conn.execute("INSERT INTO daily_stats(day, total_bytes) VALUES(?,?) "
                     "ON CONFLICT(day) DO UPDATE SET total_bytes=excluded.total_bytes",
                     (today, total))
        conn.commit()
        conn.close()
    except Exception:
        pass


def _get_chart_data():
    # Return [(label, bytes, pct, gb), ...] for last 7 days + top users.
    try:
        conn = get_db()
        days = []
        today = datetime.now().date()
        for i in range(6, -1, -1):
            d = today - timedelta(days=i)
            key = d.strftime('%Y-%m-%d')
            row = conn.execute('SELECT total_bytes FROM daily_stats WHERE day=?',
                               (key,)).fetchone()
            total = row['total_bytes'] if row else 0
            label = 'Today' if i == 0 else str(i)
            days.append({'label': label, 'bytes': total})
        top = conn.execute('SELECT username, used_bytes, traffic_limit_mb FROM users '
                           'WHERE used_bytes > 0 ORDER BY used_bytes DESC LIMIT 5').fetchall()
        conn.close()
        peak = max((d['bytes'] for d in days), default=0)
        for d in days:
            d['pct'] = int(d['bytes'] * 100 / peak) if peak else 0
            d['gb'] = round(d['bytes'] / (1024.0 ** 3), 2)
        top_users = []
        for r in top:
            lim = r['traffic_limit_mb'] or 0
            pct = min(int(r['used_bytes'] * 100 / (lim * 1024 * 1024)), 100) if lim else 100
            top_users.append({'username': r['username'],
                              'used': fmt_traffic(r['used_bytes']),
                              'pct': pct})
        return days, top_users
    except Exception:
        return [], []



def _hardware_stats():
    import os
    try:
        # CPU: sample /proc/stat twice over 200ms
        def cpu_times():
            with open('/proc/stat') as fh:
                parts = fh.readline().split()[1:]
            vals = [int(x) for x in parts]
            idle = vals[3] + (vals[4] if len(vals) > 4 else 0)
            return sum(vals), idle
        import time
        t1, i1 = cpu_times()
        time.sleep(0.2)
        t2, i2 = cpu_times()
        cpu = int((1 - (i2 - i1) / max(t2 - t1, 1)) * 100)
        cpu = max(0, min(cpu, 100))
    except Exception:
        cpu = 0
    try:
        with open('/proc/meminfo') as fh:
            mem = {}
            for line in fh:
                p = line.split(':')
                if len(p) == 2:
                    mem[p[0]] = int(p[1].strip().split()[0])
        total = mem.get('MemTotal', 0)
        avail = mem.get('MemAvailable', 0)
        used = total - avail
        ram = int(used * 100 / total) if total else 0
        def fmt(kb):
            gb = kb / (1024 * 1024)
            return ('%.1f GB' % gb) if gb < 10 else ('%d GB' % round(gb))
        ram_used = fmt(used)
        ram_total = fmt(total)
    except Exception:
        ram, ram_used, ram_total = 0, '?', '?'
    return {'cpu': cpu, 'ram': ram, 'ram_used': ram_used, 'ram_total': ram_total}


@app.route('/')
@login_required
def index():
    conn = get_db()
    try:
        rows = conn.execute('SELECT * FROM users ORDER BY id DESC').fetchall()
    finally:
        conn.close()
    try:
        online_users = set(os.listdir(SESS_DIR))
    except OSError:
        online_users = set()
    users, active_count = [], 0
    for row in rows:
        u = user_row_to_dict(row)
        u['online'] = row['username'] in online_users
        if not u['expired'] and not u['quota_exceeded']: active_count += 1
        users.append(u)
    total_used = sum((row['used_bytes'] or 0) for row in rows)
    total_limit_mb = sum((row['traffic_limit_mb'] or 0) for row in rows
                         if row['traffic_limit_mb'])
    def_dns = _default_dns()
    _record_daily_stats()
    chart_days, top_users = _get_chart_data()
    expired_count = sum(1 for row in rows
                       if row['expires_at'] <= datetime.now().strftime(DT_FMT))
    svc = {'ipsec': service_active('strongswan-starter') or service_active('ipsec'), 'xl2tpd': service_active('xl2tpd'), 'nat': service_active('l2tp-nat'), 'ocserv': service_active('ocserv'), 'ikev2': service_active('strongswan-starter') or service_active('ipsec')}
    return render_template('index.html', users=users, server_ip=SERVER_IP, psk=CFG['psk'],
                           active_count=active_count, total_count=len(users),
                           online_count=len(online_users), svc=svc, hw=_hardware_stats(),
                           total_used=fmt_traffic(total_used), total_used_gb=fmt_gb(total_used),
                           total_limit=(fmt_traffic(total_limit_mb * 1024 * 1024) if total_limit_mb else None),
                           default_dns1=def_dns[0], default_dns2=def_dns[1],
                           admin_user=CFG['admin_user'], panel_port=_panel_port(),
                           chart_days=chart_days, top_users=top_users,
                           expired_count=expired_count)

@app.route('/u/<string:key>')
def user_status(key):
    if not KEY_RE.match(key): abort(404)
    conn = get_db()
    try:
        row = conn.execute('SELECT * FROM users WHERE dns_key = ?', (key,)).fetchone()
    finally:
        conn.close()
    if row is None: abort(404)
    ud = user_row_to_dict(row)
    used_b = row['used_bytes'] or 0
    limit_b = (row['traffic_limit_mb'] or 0) * 1024 * 1024
    used_gb = round(used_b / (1024.0 ** 3), 2)
    left_gb = round(max(limit_b - used_b, 0) / (1024.0 ** 3), 2)
    oc_tcp = ''
    try:
        import re as _re
        _conf = open('/etc/ocserv/ocserv.conf').read()
        _m = _re.search(r'^\s*tcp-port\s*=\s*(\d+)', _conf, _re.M)
        if _m: oc_tcp = _m.group(1)
    except Exception:
        pass
    return render_template('user.html', u=ud, server_ip=SERVER_IP, psk=CFG['psk'],
                           used_gb=used_gb, left_gb=left_gb, oc_tcp=oc_tcp)

@app.route('/add', methods=['POST'])
@login_required
def add_user():
    username = request.form.get('username', '').strip()
    password = request.form.get('password', '').strip()
    days_raw = request.form.get('days', '').strip()
    exact = request.form.get('expires_at', '').strip()
    traffic_raw = request.form.get('traffic', '').strip()
    dns1 = request.form.get('dns1', '').strip()
    dns2 = request.form.get('dns2', '').strip()
    if not USERNAME_RE.match(username):
        flash_i18n("نام کاربری نامعتبر است.", "Invalid username."); return redirect(url_for('clients_page'))
    if BAD_PW_CHARS & set(password):
        flash(T('bad_pw_chars')); return redirect(url_for('clients_page'))
    if not password: password = gen_password()
    for d in (dns1, dns2):
        if d and not IPV4_RE.match(d):
            flash_i18n("آدرس DNS نامعتبر است.", "Invalid DNS address."); return redirect(url_for('clients_page'))
    limit_mb = parse_traffic_gb(traffic_raw)
    if traffic_raw and limit_mb is None:
        flash_i18n("محدودیت حجم نامعتبر است.", "Invalid traffic limit."); return redirect(url_for('clients_page'))
    now = datetime.now()
    if exact:
        expires_dt = parse_dt(exact)
        if expires_dt is None:
            flash_i18n("قالب تاریخ انقضا نامعتبر است.", "Invalid expiry format."); return redirect(url_for('clients_page'))
    else:
        try: days = int(days_raw)
        except ValueError: days = 0
        if days <= 0 or days > 3650:
            flash(T('invalid_days')); return redirect(url_for('clients_page'))
        expires_dt = now + timedelta(days=days)
    telegram = request.form.get('telegram', '').strip()[:64]
    protocol = request.form.get('protocol', 'all').strip()
    if protocol not in ('all', 'openconnect', 'l2tp', 'ikev2'):
        protocol = 'all'
    try:
        max_dev = int(request.form.get('max_devices', '0') or '0')
    except ValueError:
        max_dev = 0
    if max_dev < 0 or max_dev > 10:
        max_dev = 0
    note = request.form.get('note', '').strip()[:500]
    try:
        db_execute('INSERT INTO users (username, password, expires_at, created_at, '
                   'traffic_limit_mb, dns1, dns2, dns_key, telegram, protocol, max_devices, note) '
                   'VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
                   (username, password, expires_dt.strftime(DT_FMT), now.strftime(DT_FMT),
                    limit_mb, dns1, dns2, gen_key(20), telegram, protocol, max_dev, note))
    except sqlite3.IntegrityError:
        flash_i18n("نام کاربری «" + username + "» قبلاً ثبت شده است.", "Username "" + username + "" already exists."); return redirect(url_for('clients_page'))
    run_sync()
    flash_i18n("کاربر «" + username + "» اضافه شد. رمز عبور: " + password + "", "User "" + username + "" added. Password: " + password + "")
    return redirect(url_for('clients_page'))

@app.route('/renew/<int:user_id>', methods=['POST'])
@login_required
def renew_user(user_id):
    try: days = int(request.form.get('days', ''))
    except ValueError: days = 0
    if days <= 0 or days > 3650:
        flash_i18n("تعداد روز نامعتبر است.", "Invalid number of days."); return redirect(url_for('clients_page'))
    conn = get_db()
    try:
        row = conn.execute('SELECT expires_at FROM users WHERE id = ?', (user_id,)).fetchone()
    finally:
        conn.close()
    if row is None:
        flash_i18n("کاربر پیدا نشد.", "User not found."); return redirect(url_for('clients_page'))
    current = datetime.strptime(row['expires_at'], DT_FMT)
    base = current if current > datetime.now() else datetime.now()
    db_execute('UPDATE users SET expires_at = ? WHERE id = ?',
               ((base + timedelta(days=days)).strftime(DT_FMT), user_id))
    run_sync()
    # rebuild ocpasswd so renewed user can reconnect (without restarting ocserv)
    subprocess.Popen(['/usr/bin/python3', '/root/ocserv-enforce.py'],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL); flash_i18n("اعتبار کاربر تمدید شد.", "User renewed successfully.")
    return redirect(url_for('clients_page'))

@app.route('/edit/<int:user_id>', methods=['POST'])
@login_required
def edit_user(user_id):
    exact = request.form.get('expires_at', '').strip()
    password = request.form.get('password', '').strip()
    traffic_raw = request.form.get('traffic', '').strip()
    dns1 = request.form.get('dns1', '').strip()
    dns2 = request.form.get('dns2', '').strip()
    key_raw = request.form.get('key', '').strip()
    if not any((exact, password, traffic_raw, dns1, dns2, key_raw)):
        flash_i18n("چیزی برای تغییر وارد نشده است.", "Nothing to change."); return redirect(url_for('clients_page'))
    conn = get_db()
    try:
        row = conn.execute('SELECT username FROM users WHERE id = ?', (user_id,)).fetchone()
    finally:
        conn.close()
    if row is None:
        flash_err("کاربر پیدا نشد.", "User not found."); return redirect(url_for('clients_page'))
    changed_pw = False
    if exact:
        dt = parse_dt(exact)
        if dt is None:
            flash_i18n("قالب تاریخ نامعتبر است.", "Invalid date format."); return redirect(url_for('clients_page'))
        db_execute('UPDATE users SET expires_at = ? WHERE id = ?', (dt.strftime(DT_FMT), user_id))
    if password:
        if BAD_PW_CHARS & set(password):
            flash_i18n("رمز عبور دارای کاراکترهای غیرمجاز است.", "Password contains invalid characters."); return redirect(url_for('clients_page'))
        db_execute('UPDATE users SET password = ? WHERE id = ?', (password, user_id))
        changed_pw = True
    if traffic_raw:
        limit_mb = parse_traffic_gb(traffic_raw)
        if limit_mb is None:
            flash_err("محدودیت حجم نامعتبر است.", "Invalid traffic limit."); return redirect(url_for('clients_page'))
        db_execute('UPDATE users SET traffic_limit_mb = ? WHERE id = ?', (limit_mb, user_id))
    for d in (dns1, dns2):
        if d and not IPV4_RE.match(d):
            flash_err("آدرس DNS نامعتبر است.", "Invalid DNS address."); return redirect(url_for('clients_page'))
    db_execute('UPDATE users SET dns1 = ?, dns2 = ? WHERE id = ?', (dns1, dns2, user_id))
    telegram = request.form.get('telegram', '').strip()[:64]
    protocol = request.form.get('protocol', 'all').strip()
    if protocol not in ('all', 'openconnect', 'l2tp', 'ikev2'):
        protocol = 'all'
    try:
        max_dev = int(request.form.get('max_devices', '0') or '0')
    except ValueError:
        max_dev = 0
    note = request.form.get('note', '').strip()[:500]
    db_execute('UPDATE users SET telegram = ?, protocol = ?, max_devices = ?, note = ? WHERE id = ?',
               (telegram, protocol, max_dev, note, user_id))
    if key_raw:
        if not KEY_RE.match(key_raw):
            flash_i18n("کد کاربر نامعتبر است.", "Invalid user key."); return redirect(url_for('clients_page'))
        db_execute('UPDATE users SET dns_key = ? WHERE id = ?', (key_raw, user_id))
    if changed_pw: kill_session(row['username'])
    run_sync(); flash_i18n("تغییرات ذخیره شد.", "Changes saved.")
    return redirect(url_for('clients_page'))

@app.route('/regen-key/<int:user_id>', methods=['POST'])
@login_required
def regen_key(user_id):
    db_execute('UPDATE users SET dns_key = ? WHERE id = ?', (gen_key(20), user_id))
    flash_i18n("کد جدید تولید شد (لینک قبلی دیگر کار نمی‌کند).", "New key generated (old link is invalid now).")
    return redirect(url_for('clients_page'))

@app.route('/reset-traffic/<int:user_id>', methods=['POST'])
@login_required
def reset_traffic(user_id):
    db_execute('UPDATE users SET used_bytes = 0 WHERE id = ?', (user_id,))
    run_sync(); flash_i18n("شمارنده حجم کاربر صفر شد.", "Traffic counter reset.")
    return redirect(url_for('clients_page'))

@app.route('/delete/<int:user_id>', methods=['POST'])
@login_required
def delete_user(user_id):
    conn = get_db()
    try:
        row = conn.execute('SELECT username FROM users WHERE id = ?', (user_id,)).fetchone()
    finally:
        conn.close()
    db_execute('DELETE FROM users WHERE id = ?', (user_id,))
    if row: kill_session(row['username'])
    run_sync(); flash_i18n("کاربر حذف شد.", "User deleted.")
    return redirect(url_for('clients_page'))

@app.route('/sync', methods=['POST'])
@login_required
def sync_now():
    run_sync(); flash_i18n("همگام‌سازی انجام شد.", "Sync completed.")
    return redirect(url_for('clients_page'))

@app.route('/restart-vpn', methods=['POST'])
@login_required
def restart_vpn():
    ok1 = restart_service('strongswan-starter') or restart_service('ipsec')
    ok2 = restart_service('xl2tpd')
    ok4 = restart_service('ocserv')
    ok3 = restart_service('l2tp-nat')
    run_sync()
    flash(T('vpn_restarted') if ok1 and ok2 and ok3 else T('vpn_restart_failed'))
    return redirect(url_for('index'))

@app.route('/restart-panel', methods=['POST'])
@login_required
def restart_panel():
    subprocess.Popen(['/bin/sh', '-c', 'sleep 2; systemctl restart l2tp-panel'],
                     start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return render_template('restarting.html')

@app.route('/update', methods=['POST'])
@login_required
def panel_update():
    # 1) download latest installer from GitHub
    try:
        req = urllib.request.Request(UPDATE_URL, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=30) as r:
            data = r.read()
        fd, tmp_path = tempfile.mkstemp(suffix='.sh')
        with os.fdopen(fd, 'wb') as f:
            f.write(data)
        os.chmod(tmp_path, 0o600)
    except Exception:
        flash(T('update_failed'))
        return redirect(url_for('index'))
    # 2) read current panel port from systemd service
    port = '8080'
    try:
        with open('/etc/systemd/system/l2tp-panel.service') as fh:
            m = re.search(r'--bind\s+\S+?:(\d+)', fh.read())
        if m: port = m.group(1)
    except OSError:
        pass
    # 3) run installer unattended in background (shlex = safe quoting)
    cmd = ('sleep 2; bash {f} --user {u} --pass {p} --psk {k} --port {o} '
           '--tz n --no-ufw >> {log} 2>&1; rm -f {f}').format(
        f=shlex.quote(tmp_path), u=shlex.quote(CFG['admin_user']),
        p=shlex.quote(CFG['admin_pass']), k=shlex.quote(CFG['psk']),
        o=shlex.quote(port), log=shlex.quote(UPDATE_LOG))
    subprocess.Popen(['/bin/sh', '-c', cmd], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return render_template('updating.html')


def _save_config():
    try:
        with open(os.path.join(BASE, 'config.json'), 'w', encoding='utf-8') as fh:
            json.dump(CFG, fh, ensure_ascii=False, indent=2)
        os.chmod(os.path.join(BASE, 'config.json'), 0o600)
    except Exception:
        pass


def _default_dns():
    vals = []
    try:
        with open('/etc/ppp/options.xl2tpd') as fh:
            for line in fh:
                if line.strip().startswith('ms-dns'):
                    parts = line.split()
                    if len(parts) > 1:
                        vals.append(parts[1].strip())
    except OSError:
        pass
    return (vals[0] if len(vals) > 0 else '', vals[1] if len(vals) > 1 else '')


def _panel_port():
    try:
        with open('/etc/systemd/system/l2tp-panel.service') as fh:
            m = re.search(r'--bind\s+\S+?:(\d+)', fh.read())
        if m:
            return m.group(1)
    except OSError:
        pass
    return '8080'


@app.route('/settings/credentials', methods=['POST'])
@login_required
def settings_credentials():
    new_user = request.form.get('new_username', '').strip()
    new_pass = request.form.get('new_password', '')
    new_pass2 = request.form.get('new_password2', '')
    if new_pass or new_pass2:
        if new_pass != new_pass2:
            flash_i18n("رمزهای جدید یکسان نیستند.", "Passwords do not match.")
            return redirect(url_for('settings_page'))
        if BAD_PW_CHARS & set(new_pass):
            flash(T('bad_pw_chars'))
            return redirect(url_for('settings_page'))
        if len(new_pass) < 6:
            flash_err("رمز جدید باید حداقل ۶ کاراکتر باشد.", "Password must be at least 6 characters.")
            return redirect(url_for('settings_page'))
    if new_user and not USERNAME_RE.match(new_user):
        flash_err("نام کاربری نامعتبر است.", "Invalid username.")
        return redirect(url_for('settings_page'))
    if not new_user and not new_pass:
        flash_err("چیزی برای تغییر وارد نشده است.", "Nothing to change.")
        return redirect(url_for('settings_page'))
    changed = False
    if new_user and new_user != CFG['admin_user']:
        CFG['admin_user'] = new_user
        changed = True
    if new_pass:
        CFG['admin_pass'] = new_pass
        changed = True
    _save_config()
    if changed:
        session.clear()
        return redirect(url_for('login') + '?relogin=1')
    flash_i18n("تغییرات ذخیره شد.", "Changes saved.")
    return redirect(url_for('settings_page'))


@app.route('/settings/psk', methods=['POST'])
@login_required
def settings_psk():
    new_psk = request.form.get('new_psk', '').strip()
    if not new_psk or len(new_psk) < 8 or BAD_PW_CHARS & set(new_psk):
        flash_i18n("PSK نامعتبر است.", "Invalid PSK.")
        return redirect(url_for('settings_page'))
    CFG['psk'] = new_psk
    _save_config()
    try:
        with open('/etc/ipsec.secrets', 'w') as fh:
            fh.write('%%any %%any : PSK "%s"\n' % new_psk)
        os.chmod('/etc/ipsec.secrets', 0o600)
        subprocess.run(['systemctl', 'restart', 'strongswan-starter'],
                       capture_output=True, timeout=60)
    except Exception:
        pass
    flash_i18n("PSK جدید ذخیره شد و سرویس IPSec ریستارت شد.", "New PSK saved; IPSec restarted.")
    return redirect(url_for('settings_page'))


@app.route('/settings/dns', methods=['POST'])
@login_required
def settings_dns():
    dns1 = request.form.get('dns1', '').strip()
    dns2 = request.form.get('dns2', '').strip()
    for d in (dns1, dns2):
        if d and not IPV4_RE.match(d):
            flash_err("آدرس DNS نامعتبر است.", "Invalid DNS address.")
            return redirect(url_for('settings_page'))
    try:
        path = '/etc/ppp/options.xl2tpd'
        with open(path) as fh:
            lines = fh.readlines()
        kept = [ln for ln in lines if not ln.strip().startswith('ms-dns')]
        new_lines = []
        inserted = False
        for ln in kept:
            new_lines.append(ln)
            if not inserted and ln.strip().startswith('ipcp-accept-remote'):
                if dns1:
                    new_lines.append('ms-dns %s\n' % dns1)
                if dns2:
                    new_lines.append('ms-dns %s\n' % dns2)
                inserted = True
        if not inserted:
            if dns1:
                new_lines.append('ms-dns %s\n' % dns1)
            if dns2:
                new_lines.append('ms-dns %s\n' % dns2)
        with open(path, 'w') as fh:
            fh.writelines(new_lines)
        subprocess.run(['systemctl', 'restart', 'xl2tpd'],
                       capture_output=True, timeout=60)
    except Exception:
        flash_i18n("ریستارت ناموفق!", "Restart failed!")
        return redirect(url_for('settings_page'))
    flash_i18n("DNS پیش‌فرض ذخیره شد.", "Default DNS saved.")
    return redirect(url_for('settings_page'))


@app.route('/settings/port', methods=['POST'])
@login_required
def settings_port():
    port = request.form.get('port', '').strip()
    if not port.isdigit() or not (1024 <= int(port) <= 65535):
        flash_err("پورت نامعتبر است.", "Invalid port.")
        return redirect(url_for('settings_page'))
    if port == _panel_port():
        flash_err("چیزی برای تغییر وارد نشده است.", "Nothing to change.")
        return redirect(url_for('settings_page'))
    try:
        svc_path = '/etc/systemd/system/l2tp-panel.service'
        with open(svc_path) as fh:
            content = fh.read()
        content = re.sub(r'--bind\s+\S+?:(\d+)', '--bind 0.0.0.0:' + port, content)
        with open(svc_path, 'w') as fh:
            fh.write(content)
        subprocess.run(['systemctl', 'daemon-reload'], capture_output=True, timeout=30)
        subprocess.run(['ufw', 'allow', port + '/tcp'], capture_output=True, timeout=30)
    except Exception:
        flash_i18n("ریستارت ناموفق!", "Restart failed!")
        return redirect(url_for('settings_page'))
    new_url = 'http://%s:%s/' % (request.host.split(':')[0], port)
    try:
        subprocess.run(['systemd-run', '--collect', '--unit=l2tp-portchg',
                        '/bin/sh', '-c', 'sleep 1; systemctl restart l2tp-panel'],
                       capture_output=True, timeout=15)
    except Exception:
        subprocess.Popen(['/bin/sh', '-c', 'sleep 1; systemctl restart l2tp-panel'],
                         start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    html = ('<!doctype html><html><head><meta charset="utf-8">'
            '<meta http-equiv="refresh" content="4;url=%s"><title>OK</title></head>'
            '<body style="font-family:Tahoma;background:#020203;color:#f0f0f0;'
            'display:grid;place-items:center;height:100vh;margin:0">'
            '<div style="background:rgba(8,8,12,.7);border:1px solid rgba(0,229,255,.2);'
            'padding:40px 50px;border-radius:20px;text-align:center">'
            '<div style="font-size:2.4rem">&#10004;</div>'
            '<h2 style="margin:14px 0 8px">Port changed</h2>'
            '<p style="color:#7a7a8c;font-size:.85rem">Redirecting...</p>'
            '<p style="margin-top:10px"><a href="%s" style="color:#00e5ff">%s</a></p>'
            '</div></body></html>') % (new_url, new_url, new_url)
    return html


@app.route('/backup')
@login_required
def backup():
    import io, zipfile
    from flask import send_file
    buf = io.BytesIO()
    try:
        with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as zf:
            zf.write(DB_FILE, 'users.db')
            zf.write(os.path.join(BASE, 'config.json'), 'config.json')
        buf.seek(0)
        stamp = datetime.now().strftime('%Y%m%d-%H%M%S')
        return send_file(buf, as_attachment=True,
                         download_name='3outhboy-backup-%s.zip' % stamp,
                         mimetype='application/zip')
    except Exception:
        flash(T('update_failed'))
        return redirect(url_for('index'))



@app.route('/settings/restore', methods=['POST'])
@login_required
def restore_backup():
    import io as _io, zipfile as _zip
    f = request.files.get('backup_file')
    if not f or not f.filename:
        flash(T('restore_no_file'))
        return redirect(url_for('index'))
    data = f.read()
    if len(data) > 50 * 1024 * 1024:
        flash(T('restore_bad_file'))
        return redirect(url_for('index'))
    try:
        zf = _zip.ZipFile(_io.BytesIO(data))
        names = zf.namelist()
        if 'users.db' not in names:
            flash(T('restore_bad_file'))
            return redirect(url_for('index'))
    except Exception:
        flash(T('restore_bad_file'))
        return redirect(url_for('index'))
    # safety: backup current state first
    stamp = datetime.now().strftime('%Y%m%d-%H%M%S')
    try:
        os.rename(DB_FILE, DB_FILE + '.pre-restore-' + stamp)
    except OSError:
        pass
    # restore database
    with open(DB_FILE, 'wb') as out:
        out.write(zf.read('users.db'))
    # restore config if present (admin + psk)
    new_user = new_pass = new_psk = None
    if 'config.json' in names:
        try:
            cfg = json.loads(zf.read('config.json').decode('utf-8'))
            new_user = cfg.get('admin_user')
            new_pass = cfg.get('admin_pass')
            new_psk = cfg.get('psk')
            for k in ('admin_user', 'admin_pass', 'psk'):
                if cfg.get(k):
                    CFG[k] = cfg[k]
            _save_config()
        except Exception:
            pass
    # restore PSK into ipsec.secrets
    if new_psk:
        try:
            with open('/etc/ipsec.secrets', 'w') as fh:
                fh.write('%%any %%any : PSK "%s"\n' % new_psk)
            os.chmod('/etc/ipsec.secrets', 0o600)
            subprocess.run(['systemctl', 'restart', 'strongswan-starter'],
                           capture_output=True, timeout=60)
        except Exception:
            pass
    run_sync()
    if new_user and new_user != CFG.get('admin_user'):
        pass
    flash(T('restore_done'))
    if new_pass:
        session.clear()
        return redirect(url_for('login') + '?relogin=1')
    return redirect(url_for('index'))


@app.route('/clients')
@login_required
def clients_page():
    now = datetime.now()
    conn = get_db()
    try:
        rows = conn.execute('SELECT * FROM users ORDER BY created_at ASC, id ASC').fetchall()
    finally:
        conn.close()
    try:
        online_users = set(os.listdir(SESS_DIR))
    except OSError:
        online_users = set()
    users, active_count, expiring, expired_c = [], 0, 0, 0
    for row in rows:
        u = user_row_to_dict(row)
        u['online'] = row['username'] in online_users
        if not u['expired'] and not u['quota_exceeded']:
            active_count += 1
            if u['soon']:
                expiring += 1
        if u['expired'] or u['quota_exceeded']:
            expired_c += 1
        users.append(u)
    svc = {'ipsec': service_active('strongswan-starter') or service_active('ipsec'),
           'xl2tpd': service_active('xl2tpd'), 'nat': service_active('l2tp-nat'),
           'ocserv': service_active('ocserv'),
           'ikev2': service_active('strongswan-starter') or service_active('ipsec')}
    return render_template('clients.html', admin_user=CFG['admin_user'], users=users, server_ip=SERVER_IP, psk=CFG['psk'],
                           active_count=active_count, total_count=len(users),
                           online_count=len(online_users),
                           expiring_count=expiring, expired_count=expired_c, svc=svc)



@app.route('/nodes')
@login_required
def nodes_page():
    svc = {'ipsec': service_active('strongswan-starter') or service_active('ipsec'),
           'xl2tpd': service_active('xl2tpd'), 'nat': service_active('l2tp-nat'),
           'ocserv': service_active('ocserv'),
           'ikev2': service_active('strongswan-starter') or service_active('ipsec')}
    return render_template('nodes.html', server_ip=SERVER_IP, psk=CFG['psk'],
                           admin_user=CFG['admin_user'], hw=_hardware_stats(),
                           active_count=0, total_count=0, online_count=0, svc=svc)





def _firewall_state():
    fw = CFG.get('firewall', {})
    return {'block_ir': fw.get('block_ir', False),
            'block_p2p': fw.get('block_p2p', False),
            'block_ads': fw.get('block_ads', False)}


@app.route('/settings/ocserv-ports', methods=['POST'])
@login_required
def settings_ocserv_ports():
    import subprocess as sp
    tcp = request.form.get('ocserv_tcp', '').strip()
    udp = request.form.get('ocserv_udp', '').strip()
    for p in (tcp, udp):
        if not p.isdigit() or not (1 <= int(p) <= 65535):
            flash_err("پورت نامعتبر است (۱ تا ۶۵۵۳۵).", "Invalid port (1-65535).")
            return redirect(url_for('settings_page'))
    if tcp == udp:
        flash_err("پورت TCP و UDP نمی‌توانند یکسان باشند.", "TCP and UDP ports cannot be the same.")
        return redirect(url_for('settings_page'))
    try:
        conf = '/etc/ocserv/ocserv.conf'
        with open(conf) as fh:
            content = fh.read()
        content = re.sub(r'^tcp-port\s*=\s*\d+', 'tcp-port = ' + tcp, content, flags=re.M)
        content = re.sub(r'^udp-port\s*=\s*\d+', 'udp-port = ' + udp, content, flags=re.M)
        with open(conf, 'w') as fh:
            fh.write(content)
        # فایروال: پورت‌های جدید باز
        sp.run(['ufw', 'allow', tcp + '/tcp'], capture_output=True, timeout=30)
        sp.run(['ufw', 'allow', udp + '/udp'], capture_output=True, timeout=30)
        # ری‌استارت ocserv
        sp.run(['systemctl', 'restart', 'ocserv'], capture_output=True, timeout=30)
        import time as _t
        _t.sleep(2)
        ok = sp.run(['systemctl', 'is-active', 'ocserv'], capture_output=True, text=True).stdout.strip() == 'active'
        if ok:
            flash_i18n("پورت‌های OpenConnect تغییر کرد: TCP " + tcp + " / UDP " + udp,
                     "OpenConnect ports changed: TCP " + tcp + " / UDP " + udp)
        else:
            flash_err("پورت تغییر یافت اما ocserv بالا نیامد! لاگ: journalctl -u ocserv",
                      "Port changed but ocserv failed! Check: journalctl -u ocserv")
    except Exception as e:
        flash_err("خطا: " + str(e)[:80], "Error: " + str(e)[:80])
    return redirect(url_for('settings_page'))



@app.route('/settings/ipsec-params', methods=['POST'])
@login_required
def settings_ipsec_params():
    import subprocess as sp
    mtu = request.form.get('mtu', '').strip()
    cipher = request.form.get('cipher', 'aes256').strip()
    if not mtu.isdigit() or not (1200 <= int(mtu) <= 1500):
        flash_err("MTU نامعتبر است (۱۲۰۰ تا ۱۵۰۰).", "Invalid MTU (1200-1500).")
        return redirect(url_for('settings_page'))
    new_psk = request.form.get('new_psk', '').strip()
    if new_psk and (len(new_psk) < 8 or BAD_PW_CHARS & set(new_psk)):
        flash_err("PSK نامعتبر است (حداقل ۸ کاراکتر).", "Invalid PSK (min 8 chars).")
        return redirect(url_for('settings_page'))
    if not new_psk and not mtu and not cipher:
        flash_i18n("چیزی تغییر نکرد.", "Nothing changed.")
        return redirect(url_for('settings_page'))
    if cipher not in ('aes256', 'aes128', 'aes256gcm'):
        flash_err("Cipher نامعتبر است.", "Invalid cipher.")
        return redirect(url_for('settings_page'))
    try:
        # ---- ۱) xl2tpd MTU (L2TP) ----
        opts = '/etc/ppp/options.xl2tpd'
        with open(opts) as fh:
            content = fh.read()
        content = re.sub(r'^mtu\s+\d+', 'mtu ' + mtu, content, flags=re.M)
        content = re.sub(r'^mru\s+\d+', 'mru ' + mtu, content, flags=re.M)
        with open(opts, 'w') as fh:
            fh.write(content)
        # ---- ۲) ocserv MTU ----
        oc = '/etc/ocserv/ocserv.conf'
        try:
            with open(oc) as fh:
                occ = fh.read()
            if re.search(r'^mtu\s*=', occ, re.M):
                occ = re.sub(r'^mtu\s*=\s*\d+', 'mtu = ' + mtu, occ, flags=re.M)
            else:
                occ += '\nmtu = ' + mtu + '\n'
            with open(oc, 'w') as fh:
                fh.write(occ)
        except Exception:
            pass
        # ---- ۳) Cipher (ipsec.conf esp) ----
        cipher_map = {
            'aes256': 'aes256-sha2_256,aes128-sha2_256,aes256-sha1,aes128-sha1',
            'aes128': 'aes128-sha2_256,aes128-sha1',
            'aes256gcm': 'aes256gcm16,aes128gcm16,aes256-sha2_256',
        }
        ipsec_f = '/etc/ipsec.conf'
        with open(ipsec_f) as fh:
            ic = fh.read()
        ic = re.sub(r'(\s*esp\s*=\s*)[^\n]+', r'\1' + cipher_map[cipher], ic)
        with open(ipsec_f, 'w') as fh:
            fh.write(ic)
        # ---- ۳.۵) PSK (اگه تغییر کرده) ----
        if new_psk:
            CFG['psk'] = new_psk
            _save_config()
            with open('/etc/ipsec.secrets', 'w') as fh:
                fh.write('%%any %%any : PSK "%s"\n' % new_psk)
            os.chmod('/etc/ipsec.secrets', 0o600)
        # ---- ۴) ری‌استارت سرویس‌ها ----
        sp.run(['systemctl', 'restart', 'xl2tpd'], capture_output=True, timeout=30)
        sp.run(['systemctl', 'restart', 'ocserv'], capture_output=True, timeout=30)
        sp.run(['systemctl', 'restart', 'strongswan-starter'], capture_output=True, timeout=30)
        flash_i18n(("PSK، " if new_psk else "") + "MTU به " + mtu + " و Cipher به " + cipher + " تغییر کرد.",
                 "PSK, " * (1 if new_psk else 0) + "MTU to " + mtu + ", cipher: " + cipher + ".")
    except Exception as e:
        flash_err("خطا: " + str(e)[:80], "Error: " + str(e)[:80])
    return redirect(url_for('settings_page'))



def _ocserv_ports():
    tcp, udp = '555', '555'
    try:
        with open('/etc/ocserv/ocserv.conf') as fh:
            for line in fh:
                if line.startswith('tcp-port'):
                    tcp = line.split('=')[1].strip()
                elif line.startswith('udp-port'):
                    udp = line.split('=')[1].strip()
    except Exception:
        pass
    return tcp, udp


def _ipsec_params():
    mtu = '1420'
    try:
        with open('/etc/ppp/options.xl2tpd') as fh:
            m = re.search(r'^mtu\s+(\d+)', fh.read(), re.M)
            if m:
                mtu = m.group(1)
    except Exception:
        pass
    cipher = 'aes256'
    try:
        with open('/etc/ipsec.conf') as fh:
            content = fh.read()
        if 'esp=' in content:
            esp_val = content.split('esp=')[1].split('\n')[0]
            if 'gcm' in esp_val:
                cipher = 'aes256gcm'
            elif esp_val.strip().startswith('aes128'):
                cipher = 'aes128'
    except Exception:
        pass
    return mtu, cipher


@app.route('/settings')
@login_required
def settings_page():
    svc = {'ipsec': service_active('strongswan-starter') or service_active('ipsec'),
           'xl2tpd': service_active('xl2tpd'), 'nat': service_active('l2tp-nat'),
           'ocserv': service_active('ocserv'),
           'ikev2': service_active('strongswan-starter') or service_active('ipsec')}
    def_dns = _default_dns()
    ocp = _ocserv_ports()
    ip = _ipsec_params()

    try:
        _st = '/tmp/fw-apply-status'
        if os.path.exists(_st):
            _age = time.time() - os.path.getmtime(_st)
            _c = open(_st).read().strip()
            if 0 < _age < 300 and _c != 'running' and _c != getattr(settings_page, '_lastfw', None):
                settings_page._lastfw = _c
                if _c.startswith('ok'):
                    flash_bi('قوانین فایروال با موفقیت اعمال شد ✓', 'Firewall rules applied ✓')
                else:
                    flash_err('اعمال برخی قوانین ناموفق بود:' + _c.replace('fail:', ' '),
                              'Some rules failed:' + _c.replace('fail:', ' '))
    except Exception:
        pass
    return render_template('settings.html', fw_state=_firewall_state(), server_ip=SERVER_IP, psk=CFG['psk'],
                           admin_user=CFG['admin_user'], panel_port=_panel_port(),
                           default_dns1=def_dns[0], default_dns2=def_dns[1], svc=svc,
                           ocserv_tcp=ocp[0], ocserv_udp=ocp[1],
                           ipsec_mtu=ip[0], ipsec_cipher=ip[1])




@app.route('/settings/firewall', methods=['POST'])
@login_required
def settings_firewall():
    import subprocess as sp
    key = request.form.get('fw_key', '').strip()
    state = request.form.get('fw_state', '').strip()
    if key not in ('block_ir', 'block_p2p', 'block_ads') or state not in ('on', 'off'):
        flash_err("درخواست نامعتبر.", "Invalid request.")
        return redirect(url_for('settings_page'))
    what = {'block_ir': 'ir', 'block_p2p': 'p2p', 'block_ads': 'ads'}[key]
    try:
        r = sp.run(['/bin/bash', '/root/firewall-apply.sh', what, state],
                   capture_output=True, text=True, timeout=60)
        ok = r.returncode == 0
    except Exception:
        ok = False
    if ok:
        fw_cfg = CFG.get('firewall', {})
        fw_cfg[key] = (state == 'on')
        CFG['firewall'] = fw_cfg
        _save_config()
        names = {'block_ir': ('مسدودسازی سایت‌های ایرانی', 'Iranian domains block'),
                 'block_p2p': ('مسدودسازی تورنت', 'P2P block'),
                 'block_ads': ('بلاک تبلیغات یوتیوب', 'YouTube ads block')}
        fa, en = names[key]
        if state == 'on':
            flash_i18n(fa + " فعال شد.", en + " enabled.")
        else:
            flash_i18n(fa + " غیرفعال شد.", en + " disabled.")
    else:
        flash_err("اعمال قانون فایروال ناموفق بود!", "Firewall rule failed!")
    return redirect(url_for('settings_page'))



@app.route('/settings/firewall-save', methods=['POST'])
@login_required
def settings_firewall_save():
    import subprocess as sp
    block_ir = 'block_ir' in request.form
    block_p2p = 'block_p2p' in request.form
    block_ads = 'block_ads' in request.form

    # ذخیره فوری وضعیت
    CFG['firewall'] = {'block_ir': block_ir,
                       'block_p2p': block_p2p,
                       'block_ads': block_ads}
    _save_config()

    # اعمال در پس‌زمینه — دکمه فوراً جواب می‌دهد، هیچ تردی قفل نمی‌شود
    states = {'ir': 'on' if block_ir else 'off',
              'p2p': 'on' if block_p2p else 'off',
              'ads': 'on' if block_ads else 'off'}
    bg = '#!/bin/bash\nexec 9>/tmp/fw-apply.lock\nflock 9\n'
    bg += 'S=/tmp/fw-apply-status; echo running > "$S"\n'
    bg += 'FAIL=""\n'
    for k in ('ir', 'p2p', 'ads'):
        bg += '/bin/bash /root/firewall-apply.sh %s %s || FAIL="$FAIL %s"\n' % (k, states[k], k)
    bg += 'if [ -z "$FAIL" ]; then echo "ok $(date +%H:%M)" > "$S"; else echo "fail:$FAIL" > "$S"; fi\n'

    sp.Popen(['/bin/bash', '-c', bg], start_new_session=True,
             stdout=sp.DEVNULL, stderr=sp.DEVNULL)

    flash_bi("قوانین در پس‌زمینه اعمال می‌شوند؛ چند ثانیه بعد صفحه را دوباره باز کنید.",
             "Applying in background; reload this page in a few seconds.")
    return redirect(url_for('settings_page'))


init_db()

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)









ZQ_panel_py
chmod 755 "${PANEL_DIR}/panel.py"

cat > "${PANEL_DIR}/sync_users.py" <<'ZQ_sync_users_py'
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
        proto_ok = True
        try:
            proto_row = conn.execute('SELECT protocol FROM users WHERE username = ?', (username,)).fetchone()
            proto_ok = (not proto_row) or (proto_row[0] in ('all', 'l2tp'))
        except Exception:
            pass
        if time_ok and quota_ok and proto_ok:
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











ZQ_sync_users_py
chmod 755 "${PANEL_DIR}/sync_users.py"

cat > "${PANEL_DIR}/iface_down.py" <<'ZQ_iface_down_py'
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












ZQ_iface_down_py
chmod 755 "${PANEL_DIR}/iface_down.py"

cat > "${PANEL_DIR}/ocserv_online.py" <<'ZQ_ocserv_online_py'
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




ZQ_ocserv_online_py
chmod 755 "${PANEL_DIR}/ocserv_online.py"

cat > "${PANEL_DIR}/ocserv_traffic.py" <<'ZQ_ocserv_traffic_py'
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

ZQ_ocserv_traffic_py
chmod 755 "${PANEL_DIR}/ocserv_traffic.py"

cat > "${PANEL_DIR}/ocserv_manager.py" <<'ZQ_ocserv_manager_py'
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

ZQ_ocserv_manager_py
chmod 755 "${PANEL_DIR}/ocserv_manager.py"

cat > "${PANEL_DIR}/templates/base.html" <<'ZQ_base_html'
<!doctype html>
<html lang="{{ lang }}" dir="{{ dir }}" data-theme="dark">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<script>
(function(){
  var t=null;
  try{t=localStorage.getItem('l2tp-theme');}catch(e){}
  if(!t){t=(window.matchMedia&&window.matchMedia('(prefers-color-scheme: light)').matches)?'light':'dark';}
  document.documentElement.setAttribute('data-theme',t);
})();
</script>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/gh/rastikerdar/vazirmatn@v33.0.0/Vazirmatn-font-face.css" crossorigin="anonymous">
<link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg%20xmlns%3D%27http%3A//www.w3.org/2000/svg%27%20viewBox%3D%270%200%2064%2064%27%3E%3Cdefs%3E%3ClinearGradient%20id%3D%27g%27%20x1%3D%2710%27%20y1%3D%276%27%20x2%3D%2754%27%20y2%3D%2758%27%20gradientUnits%3D%27userSpaceOnUse%27%3E%3Cstop%20stop-color%3D%27%2300e5ff%27/%3E%3Cstop%20offset%3D%271%27%20stop-color%3D%27%23b026ff%27/%3E%3C/linearGradient%3E%3C/defs%3E%3Cpath%20d%3D%27M32%204%20L55.5%2012.5%20V28%20C55.5%2042.5%2046%2052.5%2032%2059.5%20C18%2052.5%208.5%2042.5%208.5%2028%20V12.5%20Z%27%20fill%3D%27url%28%23g%29%27%20fill-opacity%3D%270.15%27/%3E%3Cpath%20d%3D%27M32%204%20L55.5%2012.5%20V28%20C55.5%2042.5%2046%2052.5%2032%2059.5%20C18%2052.5%208.5%2042.5%208.5%2028%20V12.5%20Z%27%20stroke%3D%27url%28%23g%29%27%20stroke-width%3D%273.4%27%20fill%3D%27none%27/%3E%3Cpath%20d%3D%27M22%2046.5%20V29%20C22%2021.8%2026.4%2016%2032%2016%20C37.6%2016%2042%2021.8%2042%2029%20V46.5%27%20stroke%3D%27url%28%23g%29%27%20stroke-width%3D%272.6%27%20fill%3D%27none%27/%3E%3Cpath%20d%3D%27M28%2046.5%20V31.5%20C28%2027%2029.7%2023.5%2032%2023.5%20C34.3%2023.5%2036%2027%2036%2031.5%20V46.5%27%20stroke%3D%27url%28%23g%29%27%20stroke-width%3D%272%27%20fill%3D%27none%27%20opacity%3D%270.6%27/%3E%3Ccircle%20cx%3D%2732%27%20cy%3D%2736.5%27%20r%3D%273%27%20fill%3D%27url%28%23g%29%27/%3E%3C/svg%3E">
<title>{% block title %}{{ t.brand }}{% endblock %}</title>
<style>
:root{
  --bg-deep:#020203;--panel-bg:rgba(8,8,12,.7);--border-neon:rgba(0,229,255,.15);
  --neon-cyan:#00e5ff;--neon-purple:#b026ff;--btn-tx:#020203;
  --bg:#020203;--card:rgba(8,8,12,.7);--card2:rgba(255,255,255,.03);--card3:rgba(255,255,255,.06);
  --bd:rgba(0,229,255,.12);--bd2:rgba(0,229,255,.28);
  --tx:#f0f0f0;--mu:#7a7a8c;
  --acc:#00e5ff;--acc2:#b026ff;--grn:#00ff9d;--red:#ff4d6d;--org:#ffb020;
  --sh:0 10px 30px rgba(0,0,0,.5);--sh2:0 6px 18px rgba(0,0,0,.4);
  --input:rgba(0,0,0,.55);
}
[data-theme=light]{
  --bg-deep:#eef2f9;--panel-bg:#ffffff;--border-neon:#dbe6f5;
  --neon-cyan:#0b98ec;--neon-purple:#8b5cf6;--btn-tx:#ffffff;
  --bg:#eef2f9;--card:#ffffff;--card2:#f5f8fd;--card3:#ecf1fa;
  --bd:#e0e8f4;--bd2:#c5d2e8;--tx:#182238;--mu:#5d6c8a;
  --acc:#2563eb;--acc2:#8b5cf6;--grn:#16a34a;--red:#dc2626;--org:#d97706;
  --sh:0 20px 40px -15px rgba(133,189,215,.7);--sh2:0 10px 24px -10px rgba(133,189,215,.7);
  --input:#f5f8fd;
}
*{box-sizing:border-box;margin:0;padding:0}
html{scroll-behavior:smooth}
body{font-family:Vazirmatn,'Segoe UI',Tahoma,Arial,sans-serif;color:var(--tx);min-height:100vh;
  background-color:var(--bg-deep);
  background-image:radial-gradient(circle at 15% 50%,rgba(0,229,255,.035),transparent 30%),
                   radial-gradient(circle at 85% 30%,rgba(176,38,255,.035),transparent 30%);
  background-attachment:scroll;transition:background-color .25s,color .25s}
[data-theme=light] body{background-color:#eef2f9;
  background-image:linear-gradient(to bottom right,#e3f0ff,#f6f9ff)}
::-webkit-scrollbar{width:6px;height:6px}
::-webkit-scrollbar-track{background:transparent}
::-webkit-scrollbar-thumb{background:var(--neon-cyan);border-radius:10px}
[data-theme=light] ::-webkit-scrollbar-thumb{background:#a3c3e0}
html[dir=ltr] body{font-family:'Inter','SF Pro Display','Segoe UI Variable Display',system-ui,-apple-system,'Segoe UI',Roboto,Arial,sans-serif;letter-spacing:.012em}
html[dir=ltr] .gheading{letter-spacing:3px}
.container{max-width:1180px;margin:0 auto;padding:0 16px}
header{will-change:transform;background:var(--panel-bg);
  border-bottom:1px solid var(--border-neon);padding:15px 0;margin-bottom:24px;
  position:sticky;top:0;z-index:40;box-shadow:0 10px 30px rgba(0,0,0,.35)}
[data-theme=light] header{box-shadow:var(--sh2)}
.header-in{display:flex;justify-content:space-between;align-items:center;gap:10px;flex-wrap:wrap}
.brand{display:flex;align-items:center;gap:12px}
.brand-badge{width:46px;height:46px;border-radius:14px;display:grid;place-items:center;font-size:0;
  background:var(--card3);border:1px solid var(--bd2);box-shadow:0 0 16px rgba(0,229,255,.18)}
.brand-badge .logo-svg{width:31px;height:31px}
h1{font-size:1.05rem;font-weight:700;text-shadow:0 0 25px rgba(0,229,255,.35)}
[data-theme=light] h1{text-shadow:none}
h2{font-size:.98rem;margin-bottom:16px;font-weight:700;display:flex;align-items:center;gap:8px}
h2::before{content:'';width:4px;height:18px;border-radius:99px;
  background:linear-gradient(180deg,var(--neon-cyan),var(--neon-purple));
  box-shadow:0 0 8px rgba(0,229,255,.5)}
.card{background:var(--panel-bg);backface-visibility:hidden;border:1px solid var(--border-neon);border-radius:20px;
  padding:20px;margin-bottom:16px;
  box-shadow:var(--sh2);transition:border-color .35s,box-shadow .35s,transform .35s;
  position:relative;overflow:hidden}
.card::before{content:'';position:absolute;top:0;left:-100%;width:50%;height:100%;
  background:linear-gradient(90deg,transparent,rgba(255,255,255,.03),transparent);
  transform:skewX(-20deg);transition:.7s;pointer-events:none}
.card:hover::before{left:200%}
.card:hover{border-color:rgba(0,229,255,.4);
  box-shadow:0 20px 40px rgba(0,0,0,.6),0 0 25px rgba(0,229,255,.12);transform:translateY(-3px)}
[data-theme=light] .card{backdrop-filter:none}
[data-theme=light] .card:hover{border-color:var(--bd2);box-shadow:var(--sh);transform:none}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:14px}
.stat-head{display:flex;align-items:center;gap:10px;margin-bottom:10px}
.stat-icon{width:36px;height:36px;border-radius:11px;display:grid;place-items:center;font-size:1rem;
  background:var(--card3);border:1px solid var(--bd);flex:none;transition:transform .25s,opacity .25s,border-color .25s,box-shadow .25s}
.stat-label{color:var(--mu);font-size:.82rem;font-weight:600}
.stat b{font-size:1.05rem;word-break:break-all}
.btn{border:1px solid rgba(255,255,255,.08);background:var(--card2);color:var(--tx);
  border-radius:10px;padding:9px 16px;cursor:pointer;font-family:inherit;font-size:.87rem;
  font-weight:600;transition:transform .25s,opacity .25s,border-color .25s,box-shadow .25s;text-decoration:none;display:inline-flex;align-items:center;gap:6px}
.btn:hover{border-color:var(--border-neon);color:var(--acc);background:var(--card3);
  box-shadow:0 0 15px rgba(0,229,255,.12)}
.btn.primary{background:linear-gradient(135deg,var(--neon-cyan),var(--neon-purple));
  color:var(--btn-tx);border:none;box-shadow:0 0 20px rgba(0,229,255,.25)}
.btn.primary:hover{filter:brightness(1.1);box-shadow:0 0 28px rgba(0,229,255,.4);color:var(--btn-tx)}
.btn.danger{background:linear-gradient(135deg,#ef4444,#dc2626);border:none;color:#fff}
.btn.danger:hover{filter:brightness(1.1);color:#fff}
.btn.small{padding:5px 11px;font-size:.78rem;border-radius:8px}
label{display:block;font-size:.8rem;color:var(--mu);margin-bottom:6px;font-weight:600}
input{width:100%;background:var(--input);border:1px solid rgba(255,255,255,.08);color:var(--tx);
  border-radius:12px;padding:10px 13px;font-family:inherit;font-size:.9rem;
  transition:border-color .18s,box-shadow .18s}
[data-theme=light] input{border-color:var(--bd2)}
input::placeholder{color:var(--mu);opacity:.65}
input:focus{outline:none;border-color:var(--neon-cyan);box-shadow:0 0 15px rgba(0,229,255,.2)}
[data-theme=light] input:focus{box-shadow:0 0 0 3px rgba(59,130,246,.18)}
input[type=number]{text-align:center}
.add-form{display:grid;grid-template-columns:repeat(auto-fit,minmax(185px,1fr));gap:13px;align-items:end}
.add-form .full{grid-column:1/-1;display:flex;align-items:center;gap:12px;flex-wrap:wrap}
.table-wrap{overflow-x:auto;border:1px solid var(--bd);border-radius:14px}
table{width:100%;border-collapse:collapse;font-size:.86rem;min-width:940px}
th,td{padding:11px 10px;text-align:start;border-bottom:1px solid var(--bd);vertical-align:middle;white-space:nowrap}
th{color:var(--mu);font-weight:700;font-size:.74rem;text-transform:uppercase;letter-spacing:.4px;background:var(--card2)}
tbody tr{transition:background .15s}
tbody tr:hover{background:rgba(0,229,255,.03)}
[data-theme=light] tbody tr:hover{background:var(--card2)}
tbody tr:last-child td{border-bottom:none}
tr.expired{opacity:.45}
.badge{display:inline-flex;align-items:center;gap:6px;padding:4px 11px;border-radius:99px;font-size:.72rem;font-weight:700}
.badge::before{content:'';width:6px;height:6px;border-radius:50%;background:currentColor;flex:none}
.badge.green{background:rgba(0,255,157,.1);color:var(--grn)}
.badge.orange{background:rgba(255,176,32,.1);color:var(--org)}
.badge.red{background:rgba(255,77,109,.1);color:var(--red)}
[data-theme=light] .badge.green{background:#dcfce7;color:#15803d}
[data-theme=light] .badge.orange{background:#fef3c7;color:#b45309}
[data-theme=light] .badge.red{background:#fee2e2;color:#b91c1c}
.actions{display:flex;gap:6px;align-items:center;flex-wrap:wrap}
.inline{display:inline-flex;gap:6px;align-items:center}
.mini{width:62px;padding:5px 8px;font-size:.8rem;border-radius:8px}
.pw{font-family:ui-monospace,'Cascadia Code',Consolas,monospace;color:var(--mu);letter-spacing:.3px}
.secret-row{display:inline-flex;gap:6px;align-items:center;flex-wrap:wrap}
.icon-btn{background:none;border:none;cursor:pointer;font-size:.92rem;padding:3px 5px;opacity:.85;
  transition:transform .25s,opacity .25s,border-color .25s,box-shadow .25s;border-radius:6px;font-family:inherit}
.icon-btn:hover{opacity:1;transform:scale(1.12)}
.icon-btn .ni{width:1.05em;height:1.05em;vertical-align:-0.15em}
.dot{display:inline-block;width:9px;height:9px;border-radius:50%;background:var(--grn);
  margin-inline-start:7px;box-shadow:0 0 0 3px rgba(0,255,157,.22);animation:pulse 2s infinite}
@keyframes pulse{0%,100%{box-shadow:0 0 0 3px rgba(0,255,157,.22)}50%{box-shadow:0 0 0 6px rgba(0,255,157,.05)}}
.alert{padding:11px 15px;border-radius:11px;margin-bottom:14px;font-size:.87rem;font-weight:600;animation:slideIn .3s ease}
.alert.ok{background:rgba(0,255,157,.08);color:var(--grn);border:1px solid rgba(0,255,157,.3)}
[data-theme=light] .alert.ok{background:#f0fdf4;color:#166534;border-color:#bbf7d0}
@keyframes slideIn{from{opacity:0;transform:translateY(-7px)}to{opacity:1;transform:none}}
.login-wrap{min-height:100vh;display:flex;align-items:center;justify-content:center;padding:16px}
.err-box{background:rgba(255,77,109,.12);color:var(--red);border:1px solid rgba(255,77,109,.35);
  padding:10px 13px;border-radius:10px;margin:14px 0 2px;font-size:.84rem;font-weight:600;text-align:center}
[data-theme=light] .err-box{background:#fef2f2;color:#b91c1c;border-color:#fecaca}
.empty{text-align:center;color:var(--mu);padding:30px}
.modal{display:none;position:fixed;inset:0;background:rgba(2,2,3,.7);backdrop-filter:blur(5px);
  align-items:center;justify-content:center;z-index:60;padding:16px}
.modal.show{display:flex}
.modal-card{background:var(--panel-bg);backdrop-filter:blur(20px);border:1px solid var(--bd2);
  border-radius:16px;padding:22px;width:100%;max-width:370px;box-shadow:var(--sh);animation:zoomIn .22s ease}
@keyframes zoomIn{from{opacity:0;transform:scale(.95)}to{opacity:1;transform:none}}
.modal-card h3{margin-bottom:14px;font-size:1rem;display:flex;align-items:center;gap:8px}
.modal-card label{margin-top:11px}
.modal-btns{display:flex;gap:9px;margin-top:20px}
.modal-btns .btn{flex:1;justify-content:center}
.muted{color:var(--mu);font-size:.76rem}
.ctrl-cluster{position:fixed;will-change:transform;bottom:18px;inset-inline-end:18px;z-index:100;display:flex;gap:9px}
.ctrl-btn{height:34px;min-width:52px;padding:0 14px;border-radius:99px;display:inline-grid;place-items:center;
  font-size:.68rem;letter-spacing:.12em;font-weight:800;
  border:1px solid var(--bd2);background:var(--panel-bg);backdrop-filter:blur(15px);color:var(--mu);
  cursor:pointer;text-decoration:none;font-family:inherit;box-shadow:var(--sh2);transition:transform .25s,opacity .25s,border-color .25s,box-shadow .25s}
.ctrl-btn:hover{color:var(--tx);border-color:var(--neon-cyan);box-shadow:0 0 14px rgba(0,229,255,.22);transform:translateY(-2px)}
#themeBtn{color:var(--acc)}
#themeBtn:hover{color:var(--acc);filter:brightness(1.15)}
.bar{height:5px;background:rgba(255,255,255,.06);border-radius:99px;overflow:hidden;margin-top:6px;min-width:95px}
[data-theme=light] .bar{background:#e2e8f4}
.bar-fill{height:100%;border-radius:99px;background:linear-gradient(90deg,var(--neon-cyan),var(--neon-purple));
  box-shadow:0 0 12px rgba(0,229,255,.4);transition:width .6s ease}
.bar-fill.warn{background:linear-gradient(90deg,#f59e0b,#f97316);box-shadow:0 0 12px rgba(245,158,11,.4)}
.bar-fill.danger{background:linear-gradient(90deg,#ef4444,#dc2626);box-shadow:0 0 12px rgba(239,68,68,.4)}
.traffic-cell{display:flex;flex-direction:column;min-width:110px}
.lg-a{stop-color:var(--neon-cyan)}
.lg-b{stop-color:var(--neon-purple)}
.logo-svg{display:block;filter:drop-shadow(0 0 6px color-mix(in srgb,var(--neon-cyan) 45%,transparent))}
[data-theme=light] .logo-svg{filter:drop-shadow(0 0 5px color-mix(in srgb,var(--acc) 30%,transparent))}
.logo-svg circle{animation:lgpulse 2.6s ease-in-out infinite}
@keyframes lgpulse{0%,100%{opacity:1}50%{opacity:.4}}
.login-logo{width:66px;height:66px;border-radius:19px;display:grid;place-items:center;margin:0 auto 12px;
  background:var(--card3);border:1px solid var(--bd2);box-shadow:0 0 20px rgba(0,229,255,.22)}
.login-logo .logo-svg{width:44px;height:44px}
.ni{width:1.15em;height:1.15em;display:inline-block;vertical-align:-0.18em}
.reveal .ni{filter:drop-shadow(0 0 4px color-mix(in srgb,var(--neon-cyan) 45%,transparent))}
[data-theme=light] .reveal .ni{filter:drop-shadow(0 0 3px color-mix(in srgb,var(--acc) 30%,transparent))}
@media(max-width:600px){h1{font-size:.95rem}.card{padding:16px}}
@media (hover:hover) and (pointer:fine){
  *,*::before,*::after{cursor:none !important}
  .cursor-orb{position:fixed;top:0;left:0;width:34px;height:34px;border-radius:50%;
    background:radial-gradient(circle,
      color-mix(in srgb,var(--acc) 70%,transparent) 0%,
      color-mix(in srgb,var(--acc2) 60%,transparent) 48%,
      transparent 78%);
    filter:blur(4px);pointer-events:none;z-index:99999;will-change:transform;
    transition:width .25s ease,height .25s ease,opacity .2s ease}
  .cursor-orb::after{content:'';position:absolute;inset:0;margin:auto;width:8px;height:8px;
    border-radius:50%;background:var(--acc);
    box-shadow:0 0 6px var(--acc),0 0 14px var(--acc),0 0 24px color-mix(in srgb,var(--acc2) 85%,transparent)}
  .cursor-orb.hot{width:62px;height:62px}
  .cursor-orb.hot::after{width:11px;height:11px}
  .cursor-orb.click{opacity:.55}
}

/* ===== icons-glow: neon life for all icons ===== */
/* glow layer for every icon */
.ni{filter:drop-shadow(0 0 3px color-mix(in srgb,var(--neon-cyan) 38%,transparent));
    transition:filter .25s,transform .25s}
[data-theme=light] .ni{filter:drop-shadow(0 0 2px color-mix(in srgb,var(--acc) 30%,transparent))}

/* dashboard stat cards: stronger glow + pulse on the icon box */
.stat-icon .ni{width:1.35em;height:1.35em;
  filter:drop-shadow(0 0 5px color-mix(in srgb,var(--neon-cyan) 55%,transparent))}
.stat-icon:hover .ni{transform:scale(1.18);
  filter:drop-shadow(0 0 9px color-mix(in srgb,var(--neon-cyan) 75%,transparent))}
.stat-icon:hover{border-color:rgba(0,229,255,.5);box-shadow:0 0 14px rgba(0,229,255,.18)}

/* action icons (edit/trash/reset/key): grow + colored glow on hover */
.icon-btn .ni{width:1.15em;height:1.15em}
.icon-btn:hover .ni{transform:scale(1.28)}
.icon-btn:hover .ni{filter:drop-shadow(0 0 7px color-mix(in srgb,var(--neon-cyan) 70%,transparent))}

/* trash gets its red glow */
.icon-btn.danger .ni,.icon-btn:hover .danger-glow .ni{filter:drop-shadow(0 0 4px rgba(255,77,109,.4))}
.icon-btn.danger:hover .ni{transform:scale(1.28);
  filter:drop-shadow(0 0 8px rgba(255,77,109,.75))}

/* sidebar items: icon shines when active/hover */
.sb-item .ni{width:1.3em;height:1.3em;transition:transform .25s,opacity .25s,border-color .25s,box-shadow .25s}
.sb-item:hover .ni{transform:translateY(-1px) scale(1.1);
  filter:drop-shadow(0 0 7px color-mix(in srgb,var(--neon-cyan) 65%,transparent))}
.sb-item.active .ni{filter:drop-shadow(0 0 9px color-mix(in srgb,var(--neon-cyan) 85%,transparent));
  animation:iconPulse 2.6s ease-in-out infinite}
@keyframes iconPulse{
  0%,100%{filter:drop-shadow(0 0 5px color-mix(in srgb,var(--neon-cyan) 55%,transparent))}
  50%{filter:drop-shadow(0 0 12px color-mix(in srgb,var(--neon-cyan) 95%,transparent))}
}

/* section h2 icons + settings headers */
h2 .ni,.ni-lg{filter:drop-shadow(0 0 6px color-mix(in srgb,var(--neon-cyan) 50%,transparent))}

/* buttons with inline icons */
.btn .ni{width:1.05em;height:1.05em}
.btn:hover .ni{transform:scale(1.15);filter:drop-shadow(0 0 6px color-mix(in srgb,var(--neon-cyan) 65%,transparent))}
</style>
</head>
<body>
<svg width="0" height="0" style="position:absolute" aria-hidden="true">
  <defs>
    <linearGradient id="niC" x1="0" y1="0" x2="1" y2="1"><stop class="lg-a" offset="0"/><stop class="lg-b" offset="1"/></linearGradient>
    <linearGradient id="niG" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#00ff9d"/><stop offset="1" stop-color="#00e5ff"/></linearGradient>
    <linearGradient id="niR" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ff4d6d"/><stop offset="1" stop-color="#ff9a3d"/></linearGradient>
    <linearGradient id="niY" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ffb020"/><stop offset="1" stop-color="#f97316"/></linearGradient>
    <linearGradient id="niP" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#b026ff"/><stop offset="1" stop-color="#7c6bff"/></linearGradient>
  <symbol id="i-eye" viewBox="0 0 24 24"><path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z" fill="none" stroke="url(#niC)" stroke-width="1.8" stroke-linejoin="round"/><circle cx="12" cy="12" r="3" fill="url(#niC)"/></symbol>
  <symbol id="i-eyeoff" viewBox="0 0 24 24"><path d="M4.5 4.5l15 15" stroke="url(#niR)" stroke-width="2" stroke-linecap="round"/><path d="M9.9 5.9c.7-.2 1.4-.4 2.1-.4 6 0 9.5 6.5 9.5 6.5a17.3 17.3 0 0 1-3.3 4M6.6 6.7A16.7 16.7 0 0 0 2.5 12S6 18.5 12 18.5c1.2 0 2.3-.2 3.3-.6" fill="none" stroke="url(#niR)" stroke-width="1.8" stroke-linecap="round"/></symbol>
  <symbol id="i-globe" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9" fill="none" stroke="url(#niC)" stroke-width="1.8"/><ellipse cx="12" cy="12" rx="4" ry="9" fill="none" stroke="url(#niC)" stroke-width="1.4" opacity=".7"/><path d="M3.5 9h17M3.5 15h17" stroke="url(#niC)" stroke-width="1.4" opacity=".7" stroke-linecap="round"/></symbol>
  <symbol id="i-key" viewBox="0 0 24 24"><circle cx="8" cy="12" r="4" fill="none" stroke="url(#niY)" stroke-width="1.8"/><path d="M12 12h9M18 12v3.5M15 12v2.5" stroke="url(#niY)" stroke-width="1.8" stroke-linecap="round"/></symbol>
  <symbol id="i-user" viewBox="0 0 24 24"><circle cx="12" cy="8" r="4" fill="none" stroke="url(#niC)" stroke-width="1.8"/><path d="M4.5 20c1.2-3.5 4-5 7.5-5s6.3 1.5 7.5 5" fill="none" stroke="url(#niC)" stroke-width="1.8" stroke-linecap="round"/></symbol>
  <symbol id="i-users" viewBox="0 0 24 24"><circle cx="9" cy="8.5" r="3.4" fill="none" stroke="url(#niC)" stroke-width="1.7"/><path d="M2.8 19.5c1-3 3.3-4.3 6.2-4.3s5.2 1.3 6.2 4.3" fill="none" stroke="url(#niC)" stroke-width="1.7" stroke-linecap="round"/><circle cx="17" cy="9.5" r="2.7" fill="none" stroke="url(#niP)" stroke-width="1.5" opacity=".8"/><path d="M15.5 15.5c3 .3 4.9 1.6 5.7 4" fill="none" stroke="url(#niP)" stroke-width="1.5" stroke-linecap="round" opacity=".8"/></symbol>
  <symbol id="i-signal" viewBox="0 0 24 24"><path d="M4 18v-3M9 18v-6M14 18v-9M19 18V5" stroke="url(#niG)" stroke-width="2.4" stroke-linecap="round"/><path d="M3 21h18" stroke="url(#niG)" stroke-width="1.6" stroke-linecap="round" opacity=".45"/></symbol>
  <symbol id="i-gauge" viewBox="0 0 24 24"><path d="M4 16a8 8 0 1 1 16 0" fill="none" stroke="url(#niC)" stroke-width="2" stroke-linecap="round"/><path d="M12 16l4-5" stroke="url(#niC)" stroke-width="2" stroke-linecap="round"/><circle cx="12" cy="16" r="1.7" fill="url(#niC)"/></symbol>
  <symbol id="i-gear" viewBox="0 0 24 24"><circle cx="12" cy="12" r="3.2" fill="none" stroke="url(#niC)" stroke-width="1.8"/><path d="M12 2.8v3M12 18.2v3M2.8 12h3M18.2 12h3M5.5 5.5l2.1 2.1M16.4 16.4l2.1 2.1M18.5 5.5l-2.1 2.1M7.6 16.4l-2.1 2.1" stroke="url(#niC)" stroke-width="1.8" stroke-linecap="round"/></symbol>
  <symbol id="i-shield" viewBox="0 0 24 24"><path d="M12 2.5l7.5 3v6c0 5-3.2 8.6-7.5 10.5C7.7 20.1 4.5 16.5 4.5 11.5v-6z" fill="none" stroke="url(#niG)" stroke-width="1.8" stroke-linejoin="round"/><path d="M8.8 12l2.3 2.3 4.1-4.6" fill="none" stroke="url(#niG)" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></symbol>
  <symbol id="i-refresh" viewBox="0 0 24 24"><path d="M20 12a8 8 0 1 1-2.34-5.66" fill="none" stroke="url(#niC)" stroke-width="2" stroke-linecap="round"/><path d="M20 3v4.5h-4.5" fill="none" stroke="url(#niC)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></symbol>
  <symbol id="i-sync" viewBox="0 0 24 24"><path d="M4 12a8 8 0 0 1 13.66-5.66" fill="none" stroke="url(#niC)" stroke-width="2" stroke-linecap="round"/><path d="M4 3v4.5h4.5" fill="none" stroke="url(#niC)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/><path d="M20 12a8 8 0 0 1-13.66 5.66" fill="none" stroke="url(#niP)" stroke-width="2" stroke-linecap="round"/><path d="M20 21v-4.5h-4.5" fill="none" stroke="url(#niP)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></symbol>
  <symbol id="i-download" viewBox="0 0 24 24"><path d="M12 3v11M7.5 10.5L12 15l4.5-4.5" fill="none" stroke="url(#niG)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/><path d="M4 17.5V19a1.5 1.5 0 0 0 1.5 1.5h13A1.5 1.5 0 0 0 20 19v-1.5" fill="none" stroke="url(#niG)" stroke-width="2" stroke-linecap="round"/></symbol>
  <symbol id="i-trash" viewBox="0 0 24 24"><path d="M4 6.5h16M9.5 6V4.5A1.5 1.5 0 0 1 11 3h2a1.5 1.5 0 0 1 1.5 1.5V6" fill="none" stroke="url(#niR)" stroke-width="1.8" stroke-linecap="round"/><path d="M6.5 6.5l1 13a1.5 1.5 0 0 0 1.5 1.4h6a1.5 1.5 0 0 0 1.5-1.4l1-13" fill="none" stroke="url(#niR)" stroke-width="1.8" stroke-linejoin="round"/><path d="M10 10.5v6.5M14 10.5v6.5" stroke="url(#niR)" stroke-width="1.6" stroke-linecap="round" opacity=".7"/></symbol>
  <symbol id="i-edit" viewBox="0 0 24 24"><path d="M14.5 5.5l4 4L8 20H4v-4z" fill="none" stroke="url(#niY)" stroke-width="1.8" stroke-linejoin="round"/><path d="M12.5 7.5l4 4" stroke="url(#niY)" stroke-width="1.8" stroke-linecap="round"/></symbol>
  <symbol id="i-keygen" viewBox="0 0 24 24"><circle cx="8" cy="12" r="4" fill="none" stroke="url(#niP)" stroke-width="1.8"/><path d="M12 12h8.5M17 12v3M20.5 12v2" stroke="url(#niP)" stroke-width="1.8" stroke-linecap="round"/><path d="M6 6.5L7 4.7M10 6.5L9 4.7" stroke="url(#niP)" stroke-width="1.5" stroke-linecap="round" opacity=".6"/></symbol>
  <symbol id="i-server" viewBox="0 0 24 24"><rect x="3.5" y="4" width="17" height="6.5" rx="1.8" fill="none" stroke="url(#niC)" stroke-width="1.8"/><rect x="3.5" y="13.5" width="17" height="6.5" rx="1.8" fill="none" stroke="url(#niC)" stroke-width="1.8"/><circle cx="7.3" cy="7.2" r="1.15" fill="url(#niC)"/><circle cx="7.3" cy="16.8" r="1.15" fill="url(#niC)"/><path d="M11 7.2h6M11 16.8h6" stroke="url(#niC)" stroke-width="1.5" stroke-linecap="round" opacity=".6"/></symbol>
  <symbol id="i-chart" viewBox="0 0 24 24"><path d="M4 20V9M9.3 20V4M14.7 20v-8M20 20V7" stroke="url(#niC)" stroke-width="2.2" stroke-linecap="round"/><path d="M3 20h18" stroke="url(#niC)" stroke-width="1.6" stroke-linecap="round" opacity=".4"/></symbol>
  <symbol id="i-clock" viewBox="0 0 24 24"><circle cx="12" cy="12" r="8.5" fill="none" stroke="url(#niC)" stroke-width="1.8"/><path d="M12 7v5l3.5 2" fill="none" stroke="url(#niC)" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></symbol>
  <symbol id="i-cal" viewBox="0 0 24 24"><rect x="3.5" y="5" width="17" height="15.5" rx="2" fill="none" stroke="url(#niC)" stroke-width="1.8"/><path d="M3.5 9.5h17M8 3v4M16 3v4" stroke="url(#niC)" stroke-width="1.8" stroke-linecap="round"/><circle cx="8" cy="13.5" r="1" fill="url(#niC)"/><circle cx="12" cy="13.5" r="1" fill="url(#niC)"/><circle cx="16" cy="13.5" r="1" fill="url(#niC)"/><circle cx="8" cy="17" r="1" fill="url(#niC)"/><circle cx="12" cy="17" r="1" fill="url(#niC)"/></symbol>
  <symbol id="i-dns" viewBox="0 0 24 24"><path d="M12 3v18M12 3l-3 3M12 3l3 3M12 21l-3-3M12 21l3-3" stroke="url(#niP)" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" fill="none"/><circle cx="5" cy="7" r="2.2" fill="none" stroke="url(#niC)" stroke-width="1.7"/><circle cx="19" cy="7" r="2.2" fill="none" stroke="url(#niC)" stroke-width="1.7"/><circle cx="5" cy="17" r="2.2" fill="none" stroke="url(#niC)" stroke-width="1.7"/><circle cx="19" cy="17" r="2.2" fill="none" stroke="url(#niC)" stroke-width="1.7"/></symbol>
</defs>
</svg>
<div class="ctrl-cluster">
  <button type="button" class="ctrl-btn" id="themeBtn" onclick="toggleTheme()" title="{{ t.theme_tip }}">DARK</button>
  <a class="ctrl-btn" href="/lang/{{ 'en' if lang == 'fa' else 'fa' }}" title="{{ lang|upper }}">{{ 'EN' if lang == 'fa' else 'FA' }}</a>
</div>
{% block body %}{% endblock %}
<script>
function applyThemeBtn(){
  var cur=document.documentElement.getAttribute('data-theme')||'dark';
  var b=document.getElementById('themeBtn');
  if(b){b.textContent=(cur==='dark')?'LIGHT':'DARK';}
}
function toggleTheme(){
  var cur=document.documentElement.getAttribute('data-theme')||'dark';
  var next=cur==='dark'?'light':'dark';
  document.documentElement.setAttribute('data-theme',next);
  try{localStorage.setItem('l2tp-theme',next);}catch(e){}
  applyThemeBtn();
}
applyThemeBtn();
function copyText(t,b){var d=function(){var o=b.innerHTML;b.innerHTML='\u2713';setTimeout(function(){b.innerHTML=o;},1200);};if(navigator.clipboard&&window.isSecureContext){navigator.clipboard.writeText(t).then(d);}else{var a=document.createElement('textarea');a.value=t;a.style.position='fixed';a.style.opacity='0';document.body.appendChild(a);a.select();document.execCommand('copy');a.remove();d();}}
document.querySelectorAll('.copy-btn').forEach(function(b){b.addEventListener('click',function(){copyText(b.getAttribute('data-copy'),b);});});
var __E1='<svg class="ni"><use href="#i-eye"/></svg>',__E2='<svg class="ni"><use href="#i-eyeoff"/></svg>';
document.querySelectorAll('.reveal').forEach(function(b){
  b.innerHTML=__E1;
  b.addEventListener('click',function(){
    var s=b.parentElement.querySelector('.pw');
    if(s.getAttribute('data-shown')==='1'){
      s.textContent='\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022';
      s.setAttribute('data-shown','0');b.innerHTML=__E1;
    }else{
      s.textContent=s.getAttribute('data-pw');
      s.setAttribute('data-shown','1');b.innerHTML=__E2;
    }
  });
});
function genPass(){var c='ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789',a=new Uint32Array(12);window.crypto.getRandomValues(a);var p='';for(var i=0;i<12;i++){p+=c[a[i]%c.length];}document.getElementById('pw-input').value=p;}
</script>
<script>
(function(){
  if(!window.matchMedia('(hover:hover) and (pointer:fine)').matches)return;
  var o=document.createElement('div');o.className='cursor-orb';document.body.appendChild(o);
  var tx=0,ty=0,x=0,y=0;
  function loop(){
    x+=(tx-x)*0.2;y+=(ty-y)*0.2;
    o.style.transform='translate('+x+'px,'+y+'px) translate(-50%,-50%)';
    requestAnimationFrame(loop);
  }
  window.addEventListener('pointermove',function(e){tx=e.clientX;ty=e.clientY;});
  requestAnimationFrame(loop);
  var sel='button,a,input,select,textarea,label,.btn,.icon-btn,.card,.ctrl-btn,td,th';
  document.addEventListener('pointerover',function(e){if(e.target.closest(sel))o.classList.add('hot');});
  document.addEventListener('pointerout',function(e){if(e.target.closest(sel))o.classList.remove('hot');});
  document.addEventListener('pointerdown',function(){o.classList.add('click');});
  document.addEventListener('pointerup',function(){o.classList.remove('click');});
})();
</script>
{% block scripts %}{% endblock %}
</body>
</html>







ZQ_base_html

cat > "${PANEL_DIR}/templates/login.html" <<'ZQ_login_html'
<!DOCTYPE html>
<html lang="{{ lang }}" dir="{{ dir }}" class="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>3OUTHBOY | Secure Login</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script>
        tailwind.config = { 
            darkMode: 'class',
            theme: {
                extend: {
                    colors: {
                        darkBg: '#030303',
                        darkCard: '#0c0c0c',
                        darkBorder: '#1f1f1f'
                    },
                    backgroundImage: {
                        'grid-pattern': "url('data:image/svg+xml,%3Csvg width='40' height='40' viewBox='0 0 40 40' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath d='M0 0h40v40H0V0zm20 20h20v20H20V20zM0 20h20v20H0V20z' fill='%23ffffff' fill-opacity='0.02' fill-rule='evenodd'/%3E%3C/svg%3E')"
                    },
                    animation: {
                        'fade-in-up': 'fadeInUp 0.6s ease-out forwards'
                    },
                    keyframes: {
                        fadeInUp: {
                            '0%': { opacity: '0', transform: 'translateY(20px)' },
                            '100%': { opacity: '1', transform: 'translateY(0)' }
                        }
                    }
                }
            }
        }
    </script>
    <link href="https://cdn.jsdelivr.net/gh/rastikerdar/vazirmatn@v33.003/Vazirmatn-font-face.css" rel="stylesheet" />
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;700&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    
    <style>
        body { font-family: 'Vazirmatn', 'Inter', sans-serif; }
        .font-mono { font-family: 'JetBrains Mono', monospace; }
        
        .glass-card {
            background: rgba(255, 255, 255, 0.6);
            backdrop-filter: blur(20px);
            border: 1px solid rgba(255, 255, 255, 0.5);
            transition: all 0.3s ease;
        }
        .dark .glass-card {
            background: rgba(12, 12, 12, 0.65);
            backdrop-filter: blur(20px);
            border: 1px solid rgba(255, 255, 255, 0.08);
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.6);
        }
    </style>
</head>
<body class="bg-gray-50 dark:bg-darkBg text-gray-900 dark:text-gray-100 transition-colors duration-300 flex items-center justify-center min-h-screen overflow-hidden relative">

    <div class="absolute inset-0 bg-grid-pattern z-0 pointer-events-none"></div>
    <div class="absolute top-0 left-0 w-full h-full overflow-hidden z-0 pointer-events-none">
        <div class="absolute -top-[10%] -right-[10%] w-[50vw] h-[50vw] max-w-[600px] max-h-[600px] bg-cyan-600/10 rounded-full blur-[100px] animate-pulse"></div>
        <div class="absolute -bottom-[10%] -left-[10%] w-[50vw] h-[50vw] max-w-[600px] max-h-[600px] bg-purple-600/10 rounded-full blur-[100px] animate-pulse" style="animation-delay: 2s;"></div>
    </div>

    <!-- دکمه‌های کنترل (زبان و تم) -->
    <div class="absolute top-6 end-6 z-50 flex items-center gap-3">
        <a href="/lang/{{ 'en' if lang == 'fa' else 'fa' }}" class="w-10 h-10 rounded-xl bg-white/70 dark:bg-[#0f0f0f]/80 backdrop-blur-md border border-gray-200 dark:border-white/10 flex items-center justify-center hover:bg-white dark:hover:bg-white/10 transition-all font-bold text-xs shadow-sm font-mono no-underline text-gray-700 dark:text-gray-200">
            {{ 'EN' if lang == 'fa' else 'FA' }}
        </a>
        <button onclick="toggleTheme()" id="theme-icon" class="w-10 h-10 rounded-xl bg-white/70 dark:bg-[#0f0f0f]/80 backdrop-blur-md border border-gray-200 dark:border-white/10 flex items-center justify-center hover:bg-white dark:hover:bg-white/10 transition-all text-gray-600 dark:text-gray-300 shadow-sm">
            <i class="fa-solid fa-sun"></i>
        </button>
    </div>

    <!-- فرم لاگین -->
    <div class="relative w-full max-w-[420px] mx-4 z-10 animate-fade-in-up">
        <div class="glass-card rounded-[2.5rem] p-8 sm:p-10 relative overflow-hidden">
            
            <div class="absolute -top-20 -start-20 w-40 h-40 bg-purple-500/20 rounded-full blur-3xl pointer-events-none"></div>

            <!-- لوگو و عنوان -->
            <div class="flex flex-col items-center justify-center mb-10 relative z-10">
                <div class="w-16 h-16 rounded-[1.25rem] bg-gradient-to-br from-gray-900 to-black dark:from-white dark:to-gray-300 flex items-center justify-center shadow-xl border border-gray-700 dark:border-gray-100 mb-4 transform hover:scale-105 transition-transform duration-300">
                    <span class="text-white dark:text-black font-black text-4xl font-sans tracking-tighter">3</span>
                </div>
                <h1 class="font-bold text-2xl tracking-widest bg-clip-text text-transparent bg-gradient-to-r from-gray-900 to-gray-500 dark:from-white dark:to-gray-500 mb-1">3OUTHBOY</h1>
                <div class="flex items-center gap-1.5">
                    <span class="w-1.5 h-1.5 bg-cyan-500 rounded-full animate-pulse shadow-[0_0_8px_rgba(6,182,212,0.8)]"></span>
                    <span class="text-xs text-cyan-600 dark:text-cyan-400 font-mono tracking-widest font-bold">SECURE PANEL</span>
                </div>
            </div>

            <!-- پیام خطا (وقتی رمز غلط باشه) -->
            {% if error %}
            <div class="mb-6 p-4 rounded-2xl bg-red-500/10 border border-red-500/30 text-red-600 dark:text-red-400 text-sm font-bold text-center relative z-10 animate-fade-in-up">
                <i class="fa-solid fa-circle-exclamation me-2"></i>{{ error }}
            </div>
            {% endif %}

            <!-- پیام تغییر اعتبارنامه (بعد از تغییر رمز/restore) -->
            {% if relogin %}
            <div class="mb-6 p-4 rounded-2xl bg-cyan-500/10 border border-cyan-500/30 text-cyan-600 dark:text-cyan-400 text-sm font-bold text-center relative z-10 animate-fade-in-up">
                <i class="fa-solid fa-circle-info me-2"></i>{{ t.relogin_note }}
            </div>
            {% endif %}

            <!-- فرم: POST واقعی به پنل -->
            <form class="space-y-6 relative z-10" method="post" action="/login">
                
                <!-- نام کاربری -->
                <div>
                    <label class="block text-xs font-bold text-gray-600 dark:text-gray-400 mb-2 uppercase tracking-wider ps-1" data-fa="نام کاربری" data-en="Username">{{ t.username }}</label>
                    <div class="relative group">
                        <div class="absolute inset-y-0 start-0 flex items-center ps-4 pointer-events-none text-gray-400 group-focus-within:text-cyan-500 transition-colors">
                            <i class="fa-solid fa-at"></i>
                        </div>
                        <input type="text" id="username" name="username" required autocomplete="username" class="bg-gray-100/50 dark:bg-white/5 border border-gray-200 dark:border-white/10 text-sm rounded-2xl focus:ring-2 focus:ring-cyan-500/50 focus:border-cyan-500 block w-full ps-11 p-3.5 text-gray-900 dark:text-white transition-all outline-none font-mono placeholder-gray-400/70" placeholder="admin">
                    </div>
                </div>

                <!-- رمز عبور -->
                <div>
                    <label class="block text-xs font-bold text-gray-600 dark:text-gray-400 mb-2 uppercase tracking-wider ps-1" data-fa="رمز عبور" data-en="Password">{{ t.password }}</label>
                    <div class="relative group">
                        <div class="absolute inset-y-0 start-0 flex items-center ps-4 pointer-events-none text-gray-400 group-focus-within:text-purple-500 transition-colors">
                            <i class="fa-solid fa-lock"></i>
                        </div>
                        <input type="password" id="password" name="password" required autocomplete="current-password" class="bg-gray-100/50 dark:bg-white/5 border border-gray-200 dark:border-white/10 text-sm rounded-2xl focus:ring-2 focus:ring-purple-500/50 focus:border-purple-500 block w-full ps-11 pe-12 p-3.5 text-gray-900 dark:text-white transition-all outline-none font-mono placeholder-gray-400/70" placeholder="••••••••">
                        <button type="button" onclick="togglePassword()" class="absolute inset-y-0 end-0 flex items-center pe-4 text-gray-400 hover:text-gray-600 dark:hover:text-white transition-colors outline-none">
                            <i class="fa-regular fa-eye" id="eye-icon"></i>
                        </button>
                    </div>
                </div>

                <!-- به خاطر بسپار -->
                <div class="flex items-center justify-between mt-4">
                    <label class="flex items-center gap-2 cursor-pointer group">
                        <div class="relative flex items-center justify-center">
                            <input type="checkbox" name="remember" class="peer appearance-none w-5 h-5 border border-gray-300 dark:border-gray-600 rounded bg-gray-50 dark:bg-black/20 checked:bg-cyan-500 checked:border-cyan-500 transition-colors cursor-pointer">
                            <i class="fa-solid fa-check absolute text-white text-[10px] opacity-0 peer-checked:opacity-100 pointer-events-none transition-opacity"></i>
                        </div>
                        <span class="text-xs font-bold text-gray-600 dark:text-gray-400 group-hover:text-gray-900 dark:group-hover:text-white transition-colors" data-fa="مرا به خاطر بسپار" data-en="Remember me">مرا به خاطر بسپار</span>
                    </label>
                    <a href="#" class="text-xs font-bold text-cyan-600 dark:text-cyan-400 hover:underline transition-all" data-fa="رمز را فراموش کردید؟" data-en="Forgot Password?">رمز را فراموش کردید؟</a>
                </div>

                <!-- دکمه ورود -->
                <button type="submit" class="w-full bg-gradient-to-r from-cyan-600 to-purple-600 hover:from-cyan-500 hover:to-purple-500 text-white font-bold py-3.5 px-6 rounded-2xl shadow-[0_10px_25px_rgba(6,182,212,0.3)] hover:shadow-[0_15px_35px_rgba(168,85,247,0.4)] transition-all duration-300 flex items-center justify-center gap-3 tracking-wide mt-8 group">
                    <span data-fa="ورود به سیستم" data-en="Sign In to Core">{{ t.login_btn }}</span>
                    <i class="fa-solid fa-arrow-left rtl:hidden group-hover:translate-x-1 transition-transform"></i>
                    <i class="fa-solid fa-arrow-left ltr:hidden group-hover:-translate-x-1 transition-transform rotate-180"></i>
                </button>
                
            </form>
        <script>
        document.querySelector('form[action="/login"]').addEventListener('submit', function(){
            var f = document.getElementById('loginLangField');
            if (f) f.value = document.documentElement.getAttribute('lang') || 'fa';
        });
        </script>
            
            <!-- پاورقی فرم -->
            <div class="mt-8 text-center relative z-10">
                <p class="text-[10px] text-gray-500 font-mono">Secured by 3OUTHBOY Protocol &copy; 2026</p>
            </div>
        </div>
    </div>

    <script>
        // تم: با localStorage پنل هماهنگ
        (function(){
            var t = null;
            try { t = localStorage.getItem('l2tp-theme'); } catch(e) {}
            if(!t) { t = (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches) ? 'light' : 'dark'; }
            document.documentElement.classList.toggle('dark', t !== 'light');
        })();

        function toggleTheme() {
            var html = document.documentElement;
            var isDark = html.classList.contains('dark');
            html.classList.toggle('dark');
            var next = isDark ? 'light' : 'dark';
            try { localStorage.setItem('l2tp-theme', next); } catch(e) {}
        }

        // نمایش/مخفی رمز
        function togglePassword() {
            var passInput = document.getElementById('password');
            var eyeIcon = document.getElementById('eye-icon');
            if (passInput.type === 'password') {
                passInput.type = 'text';
                eyeIcon.classList.replace('fa-eye', 'fa-eye-slash');
            } else {
                passInput.type = 'password';
                eyeIcon.classList.replace('fa-eye-slash', 'fa-eye');
            }
        }
    </script>

<script>
// Auto-translate: سرور با lang درست رندر کرده (dir هم درسته)
// فقط متن‌های data-attr رو sync کن
(function autoTranslate(){
    var lang = document.documentElement.getAttribute('lang') || 'fa';
    if (lang === 'en') {
        document.querySelectorAll('[data-en]').forEach(function(el){
            el.innerText = el.getAttribute('data-en');
        });
        document.querySelectorAll('input[data-en-ph]').forEach(function(el){
            el.placeholder = el.getAttribute('data-en-ph');
        });
        // placeholder فارسی بدون data-attr:
        document.querySelectorAll('input[placeholder]').forEach(function(el){
            var p = el.getAttribute('placeholder');
            if (p === 'جستجو...') el.placeholder = 'Search...';
        });
        // فلش پیام‌ها:
        document.querySelectorAll('.flash-msg').forEach(function(el){
            var raw = el.getAttribute('data-msg') || el.textContent;
            var sep = raw.indexOf('|EN:');
            if (sep > -1) {
                var fa = raw.replace(/^ERR_FA:|^FA:/, '').substring(0, sep).replace(/^ERR_FA:|^FA:/,'');
                var en = raw.substring(sep + 4);
                var span = el.querySelector('.flash-text');
                if (span) span.textContent = en;
            }
        });
    }
})();
</script>
</body>
</html>

ZQ_login_html

cat > "${PANEL_DIR}/templates/index.html" <<'ZQ_index_html'
<!DOCTYPE html>
<html lang="{{ lang }}" dir="{{ dir }}" class="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>3OUTHBOY | Pro Network Panel</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script>
        tailwind.config = { 
            darkMode: 'class',
            theme: {
                extend: {
                    colors: { darkBg: '#030303', darkCard: '#0c0c0c', darkBorder: '#1f1f1f' },
                    backgroundImage: {
                        'grid-pattern': "url('data:image/svg+xml,%3Csvg width=\'40\' height=\'40\' viewBox=\'0 0 40 40\' xmlns=\'http://www.w3.org/2000/svg\'%3E%3Cpath d=\'M0 0h40v40H0V0zm20 20h20v20H20V20zM0 20h20v20H0V20z\' fill=\'%23ffffff\' fill-opacity=\'0.02\' fill-rule=\'evenodd\'/%3E%3C/svg%3E')"
                    }
                }
            }
        }
    </script>
    <link href="https://cdn.jsdelivr.net/gh/rastikerdar/vazirmatn@v33.003/Vazirmatn-font-face.css" rel="stylesheet" />
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;700&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    
    <style>
        body { font-family: 'Vazirmatn', 'Inter', sans-serif; }
        .font-mono { font-family: 'JetBrains Mono', monospace; }
        ::-webkit-scrollbar { width: 5px; height: 5px; }
        ::-webkit-scrollbar-track { background: transparent; }
        ::-webkit-scrollbar-thumb { background: #333; border-radius: 10px; }
        .dark ::-webkit-scrollbar-thumb:hover { background: #555; }
        .glass-card { background: rgba(255,255,255,0.6); backdrop-filter: blur(16px); border: 1px solid rgba(255,255,255,0.4); transition: all 0.3s ease; }
        .dark .glass-card { background: rgba(12,12,12,0.6); backdrop-filter: blur(16px); border: 1px solid rgba(255,255,255,0.05); box-shadow: 0 4px 30px rgba(0,0,0,0.5); }
        .dark .glass-card:hover { border-color: rgba(255,255,255,0.1); transform: translateY(-2px); }
        .chart-bar { transition: height 0.8s cubic-bezier(0.4, 0, 0.2, 1); }
        /* flash */
        .flash-msg { animation: fadeIn .3s ease; }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(-6px);} to { opacity: 1; transform: none;} }
    
    
    .sidebar-panel {
        transform: translateX(-100%);
        position: fixed;
        display: flex;
    }
    html[dir="rtl"] .sidebar-panel { transform: translateX(100%); }
    html[dir="ltr"] .sidebar-panel { transform: translateX(-100%); }
    .sidebar-panel.open { transform: translateX(0) !important; }
    @media (min-width: 1024px) {
        .sidebar-panel {
            position: static !important;
            transform: none !important;
        }
    }
    
    /* sidebar-css-fix: pure CSS sidebar */
    .sidebar-panel { transform: translateX(-100%); position: fixed; display: flex; }
    html[dir="rtl"] .sidebar-panel { transform: translateX(100%); }
    html[dir="ltr"] .sidebar-panel { transform: translateX(-100%); }
    .sidebar-panel.open { transform: translateX(0) !important; }
    @media (min-width: 1024px) {
        .sidebar-panel { position: static !important; transform: none !important; }
    }
    /* select-dark-fix */
    .dark select option { background-color: #0c0c0c; color: #f3f4f6; }
    select { color-scheme: light dark; }
    .dark select { color-scheme: dark; }
</style>
</head>
<body class="bg-gray-50 dark:bg-darkBg text-gray-900 dark:text-gray-100 transition-colors duration-300 flex h-screen overflow-hidden relative">

    <!-- پس‌زمینه -->
    <div class="absolute inset-0 bg-grid-pattern z-0 pointer-events-none"></div>
    <div class="absolute top-0 left-0 w-full h-full overflow-hidden z-0 pointer-events-none">
        <div class="absolute -top-[20%] -right-[10%] w-[50%] h-[50%] bg-blue-600/10 rounded-full blur-[120px]"></div>
        <div class="absolute bottom-[10%] -left-[10%] w-[40%] h-[40%] bg-purple-600/10 rounded-full blur-[120px]"></div>
    </div>

    <div id="sidebarOverlay" onclick="toggleSidebar()" class="fixed inset-0 bg-black/60 backdrop-blur-sm z-40 hidden transition-opacity lg:hidden"></div>

    <!-- ============ سایدبار ============ -->
    <aside id="sidebar" class="sidebar-panel fixed inset-y-0 start-0 z-50 w-72 bg-white/70 dark:bg-[#0a0a0a]/80 backdrop-blur-3xl border-e border-gray-200 dark:border-white/5 flex flex-col transition-transform duration-300 ease-out shadow-[4px_0_24px_rgba(0,0,0,0.2)]">
        <div class="h-[88px] flex items-center justify-between px-6 border-b border-gray-200/50 dark:border-white/5">
            <div class="flex items-center gap-4">
                <div class="w-11 h-11 rounded-2xl bg-gradient-to-br from-gray-900 to-black dark:from-white dark:to-gray-300 flex items-center justify-center shadow-lg border border-gray-700 dark:border-gray-100">
                    <span class="text-white dark:text-black font-black text-2xl font-sans tracking-tighter">3</span>
                </div>
                <div class="flex flex-col">
                    <span class="font-bold text-lg tracking-widest bg-clip-text text-transparent bg-gradient-to-r from-gray-900 to-gray-500 dark:from-white dark:to-gray-500">3OUTHBOY</span>
                    <span class="text-[10px] text-green-500 font-mono tracking-widest flex items-center gap-1"><span class="w-1.5 h-1.5 bg-green-500 rounded-full animate-pulse"></span> v{{ panel_version }}</span>
                </div>
            </div>
            <button onclick="toggleSidebar()" class="lg:hidden text-gray-500 hover:text-white">
                <i class="fa-solid fa-xmark text-xl"></i>
            </button>
        </div>
        
        <nav class="flex-1 p-5 space-y-2.5 overflow-y-auto">
            <p class="text-[10px] font-bold text-gray-400 dark:text-gray-500 tracking-widest px-2 mb-2" data-fa="منوی اصلی" data-en="MAIN MENU">منوی اصلی</p>
            <a href="/" class="flex items-center gap-4 px-4 py-3 bg-blue-500/10 rounded-2xl text-blue-600 dark:text-blue-400 font-bold transition-all border border-blue-500/20 shadow-inner"><i class="fa-solid fa-chart-line w-5 text-lg"></i><span data-fa="مانیتورینگ شبکه" data-en="Network Monitor">مانیتورینگ شبکه</span></a>
            <a href="/clients" class="flex items-center gap-4 px-4 py-3 hover:bg-gray-100 dark:hover:bg-white/5 rounded-2xl text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white transition-all font-medium group"><i class="fa-solid fa-users-gear w-5 text-lg"></i><span data-fa="مدیریت کلاینت‌ها" data-en="Clients Manager">مدیریت کلاینت‌ها</span></a>
            <a href="/nodes" class="flex items-center gap-4 px-4 py-3 hover:bg-gray-100 dark:hover:bg-white/5 rounded-2xl text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white transition-all font-medium group"><i class="fa-solid fa-network-wired w-5 text-lg"></i><span data-fa="نودها و سرورها" data-en="Nodes & Servers">نودها و سرورها</span></a>
            <a href="/settings" class="flex items-center gap-4 px-4 py-3 hover:bg-gray-100 dark:hover:bg-white/5 rounded-2xl text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white transition-all font-medium group"><i class="fa-solid fa-sliders w-5 text-lg"></i><span data-fa="تنظیمات هسته" data-en="Core Settings">تنظیمات هسته</span></a>
        </nav>
        
        <div class="p-6 border-t border-gray-200/50 dark:border-white/5">
            <div class="flex items-center gap-3 p-3 rounded-2xl hover:bg-gray-100 dark:hover:bg-white/5 transition-colors cursor-pointer">
                <div id="userAvatar" class="w-12 h-12 rounded-xl bg-gray-900 dark:bg-white flex items-center justify-center text-white dark:text-black font-black text-xl shadow-lg font-sans"></div>
                <div class="flex-1 overflow-hidden">
                    <p id="usernameText" class="text-sm font-bold truncate text-gray-900 dark:text-white">{{ admin_user }}</p>
                    <p class="text-xs text-gray-500 font-mono mt-0.5">Root Admin</p>
                </div>
            </div>
            <a href="/logout" class="mt-3 flex items-center justify-center gap-2 px-4 py-2.5 rounded-xl bg-red-500/10 border border-red-500/20 text-red-600 dark:text-red-400 font-bold text-sm hover:bg-red-500/20 transition-all">
                <i class="fa-solid fa-right-from-bracket"></i>
                <span data-fa="خروج" data-en="Logout">خروج</span>
            </a>
        </div>
    </aside>

    <!-- ============ محتوای اصلی ============ -->
    <main class="flex-1 flex flex-col h-screen overflow-hidden relative z-10 w-full">
        <header class="h-[88px] px-6 lg:px-10 flex items-center justify-between border-b border-gray-200/50 dark:border-white/5 bg-white/30 dark:bg-[#030303]/50 backdrop-blur-md z-30 sticky top-0">
            <div class="flex items-center gap-4">
                <button onclick="toggleSidebar()" class="lg:hidden w-10 h-10 rounded-xl bg-white dark:bg-darkCard border border-gray-200 dark:border-darkBorder flex items-center justify-center text-gray-600 dark:text-gray-300">
                    <i class="fa-solid fa-bars"></i>
                </button>
                <h1 class="text-xl font-bold hidden sm:block tracking-wide" data-fa="داشبورد عملیاتی شبکه" data-en="Network Operations Dashboard">داشبورد عملیاتی شبکه</h1>
            </div>
            
            <div class="flex items-center gap-3">
                <div class="hidden xl:flex items-center gap-2 bg-gray-100 dark:bg-white/5 p-1 rounded-xl border border-gray-200 dark:border-white/5">
                    <form method="post" action="/sync" class="inline">
                        <button type="submit" class="px-4 py-2 rounded-lg text-xs font-bold text-gray-700 dark:text-gray-300 hover:bg-white dark:hover:bg-white/10 transition-all flex items-center gap-2 shadow-sm cursor-pointer">
                            <i class="fa-solid fa-rotate text-blue-500"></i> <span data-fa="همگام‌سازی" data-en="Sync">همگام‌سازی</span>
                        </button>
                    </form>
                    <form method="post" action="/update" class="inline" onsubmit="return confirm('{{ t.update_confirm }}')">
                        <button type="submit" class="px-4 py-2 rounded-lg text-xs font-bold text-gray-700 dark:text-gray-300 hover:bg-white dark:hover:bg-white/10 transition-all flex items-center gap-2 shadow-sm cursor-pointer">
                            <i class="fa-solid fa-cloud-arrow-down text-cyan-500"></i> <span data-fa="بروزرسانی هسته" data-en="Update Core">بروزرسانی هسته</span>
                        </button>
                    </form>
                    <form method="post" action="/restart-vpn" class="inline" onsubmit="return confirm('{{ t.restart_vpn_confirm }}')">
                        <button type="submit" class="px-4 py-2 rounded-lg text-xs font-bold text-red-600 dark:text-red-400 hover:bg-white dark:hover:bg-white/10 transition-all flex items-center gap-2 shadow-sm cursor-pointer">
                            <i class="fa-solid fa-power-off"></i> <span data-fa="ریستارت سرویس" data-en="Restart Svc">ریستارت سرویس</span>
                        </button>
                    </form>
                </div>
                
                <div class="h-8 w-px bg-gray-300 dark:bg-white/10 hidden xl:block mx-2"></div>
                
                <a href="/lang/{{ 'en' if lang == 'fa' else 'fa' }}" class="w-10 h-10 rounded-xl bg-white dark:bg-[#0f0f0f] border border-gray-200 dark:border-white/10 flex items-center justify-center hover:bg-gray-50 dark:hover:bg-white/5 transition-all font-bold text-xs shadow-sm font-mono no-underline text-gray-700 dark:text-gray-200">
                    {{ 'EN' if lang == 'fa' else 'FA' }}
                </a>
                <button onclick="toggleTheme()" id="theme-icon" class="w-10 h-10 rounded-xl bg-white dark:bg-[#0f0f0f] border border-gray-200 dark:border-white/10 flex items-center justify-center hover:bg-gray-50 dark:hover:bg-white/5 transition-all text-gray-600 dark:text-gray-300 shadow-sm cursor-pointer">
                    <i class="fa-solid fa-sun"></i>
                </button>
            </div>
        </header>

        <div class="flex-1 overflow-y-auto p-4 lg:p-8 pb-20 lg:pb-10 space-y-6">
            
            <!-- flash -->
            {% with msgs = get_flashed_messages() %}
              {% for m in msgs %}
              <div class="flash-msg p-4 rounded-2xl bg-cyan-500/10 border border-cyan-500/30 text-cyan-700 dark:text-cyan-300 text-sm font-bold flex items-center gap-2">
                  <i class="fa-solid fa-circle-check"></i> {{ m }}
              </div>
              {% endfor %}
            {% endwith %}

            <!-- ردیف ۱: آمار حیاتی -->
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
                <div class="glass-card p-5 rounded-2xl relative overflow-hidden group">
                    <div class="absolute top-0 right-0 w-24 h-24 bg-cyan-500/20 rounded-full blur-2xl group-hover:bg-cyan-500/30 transition-all"></div>
                    <p class="text-[11px] font-bold text-gray-500 dark:text-gray-400 mb-1 tracking-widest uppercase" data-fa="نود مرکزی شبکه" data-en="Core Network Node">نود مرکزی شبکه</p>
                    <div class="flex items-center gap-3 mt-2">
                        <i class="fa-solid fa-server text-cyan-500"></i>
                        <p class="text-xl font-bold font-mono text-gray-900 dark:text-white">{{ server_ip }}</p>
                    </div>
                </div>

                <div class="glass-card p-4 rounded-2xl relative overflow-hidden group">
                    <div class="absolute top-0 right-0 w-20 h-20 bg-orange-500/20 rounded-full blur-2xl group-hover:bg-orange-500/30 transition-all"></div>
                    <div class="flex flex-col relative z-10">
                        <p class="text-[10px] font-bold text-gray-500 dark:text-gray-400 mb-2 tracking-widest uppercase" data-fa="کلید رمزنگاری" data-en="Encryption Key">کلید رمزنگاری</p>
                        <div class="flex items-center justify-between gap-2 bg-gray-100/70 dark:bg-black/30 rounded-xl p-2 border border-gray-200/50 dark:border-white/10">
                            <div class="flex items-center gap-2 min-w-0 flex-1">
                                <i class="fa-solid fa-shield-halved text-orange-500 text-xs flex-none"></i>
                                <p class="text-xs font-mono font-bold text-gray-700 dark:text-gray-200 truncate select-all" id="pskText" data-psk="{{ psk }}" data-shown="0" title="{{ psk }}">••••••••</p>
                            </div>
                            <div class="flex gap-1 flex-none">
                                <button onclick="togglePSK()" class="w-7 h-7 rounded-lg bg-white/80 dark:bg-white/10 border border-gray-200 dark:border-white/10 flex items-center justify-center text-gray-500 dark:text-gray-300 hover:text-orange-500 dark:hover:text-orange-400 transition-all cursor-pointer text-xs" title="Show/Hide"><i class="fa-regular fa-eye"></i></button>
                                <button onclick="copyPSK()" class="w-7 h-7 rounded-lg bg-white/80 dark:bg-white/10 border border-gray-200 dark:border-white/10 flex items-center justify-center text-gray-500 dark:text-gray-300 hover:text-orange-500 dark:hover:text-orange-400 transition-all cursor-pointer text-xs" title="Copy"><i class="fa-regular fa-copy"></i></button>
                            </div>
                        </div>
                    </div>
                </div>

                <div class="glass-card p-5 rounded-2xl relative overflow-hidden group">
                    <div class="absolute top-0 right-0 w-24 h-24 bg-blue-500/20 rounded-full blur-2xl group-hover:bg-blue-500/30 transition-all"></div>
                    <p class="text-[11px] font-bold text-gray-500 dark:text-gray-400 mb-1 tracking-widest uppercase" data-fa="کلاینت‌های برخط" data-en="Online Clients">کلاینت‌های برخط</p>
                    <div class="flex items-center gap-3 mt-2">
                        <i class="fa-solid fa-users text-blue-500"></i>
                        <p class="text-2xl font-bold font-mono text-gray-900 dark:text-white">{{ active_count }} <span class="text-xs text-gray-500 font-sans mx-1">/ {{ total_count }}</span></p>
                    </div>
                </div>

                <div class="glass-card p-5 rounded-2xl relative overflow-hidden group">
                    <div class="absolute top-0 right-0 w-24 h-24 bg-emerald-500/20 rounded-full blur-2xl group-hover:bg-emerald-500/30 transition-all"></div>
                    <p class="text-[11px] font-bold text-gray-500 dark:text-gray-400 mb-1 tracking-widest uppercase" data-fa="تونل‌های فعال" data-en="Active Tunnels">تونل‌های فعال</p>
                    <div class="flex items-center gap-3 mt-2">
                        <div class="relative">
                            <i class="fa-solid fa-bolt text-emerald-500"></i>
                            <span class="absolute -top-1 -right-2 w-2 h-2 bg-emerald-500 rounded-full animate-ping opacity-75"></span>
                        </div>
                        <p class="text-2xl font-bold font-mono text-gray-900 dark:text-white">{{ online_count }}</p>
                    </div>
                </div>
            </div>

            <!-- ردیف ۲: مصرف + سخت‌افزار -->
            <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
                
                <div class="glass-card p-6 rounded-3xl lg:col-span-2 flex flex-col md:flex-row gap-6 items-center">
                    <div class="w-full md:w-1/3 flex flex-col justify-center text-center md:text-start border-b md:border-b-0 md:border-e border-gray-200/50 dark:border-white/10 pb-6 md:pb-0 md:pe-6">
                        <div class="flex items-center justify-center md:justify-start gap-2 mb-2">
                            <span class="w-2 h-2 rounded-full bg-cyan-500 animate-pulse"></span>
                            <h3 class="text-xs font-bold text-gray-500 dark:text-gray-400 uppercase tracking-widest" data-fa="مصرف کل ترافیک" data-en="Total Traffic Usage">مصرف کل ترافیک</h3>
                        </div>
                        <div class="inline-flex items-end justify-center md:justify-start my-2">
                            <span class="text-5xl lg:text-6xl font-black font-mono tracking-tighter text-transparent bg-clip-text bg-gradient-to-br from-cyan-400 to-blue-600">{{ total_used_gb }}</span>
                            <span class="text-lg text-gray-500 font-bold mb-1 ml-1">GB</span>
                        </div>
                        <p class="text-[11px] text-gray-500 font-mono mt-1">{% if total_limit %}<span data-fa="مجموع سهم کاربران محدود: {{ total_limit }}" data-en="Total Quota: {{ total_limit }}">مجموع سهم کاربران محدود: {{ total_limit }}</span>{% else %}<span data-fa="نامحدود" data-en="Unlimited">نامحدود</span>{% endif %}</p>
                    </div>

                    <div class="w-full md:w-2/3 h-full flex flex-col justify-end">
                        <div class="flex justify-between items-center mb-4">
                            <h3 class="text-xs font-bold text-gray-500 dark:text-gray-400 uppercase tracking-widest" data-fa="روند ۷ روز گذشته" data-en="7-Day Trend">روند ۷ روز گذشته</h3>
                        </div>
                        <div class="flex-1 flex items-end justify-between gap-1.5 h-24 border-b border-gray-200 dark:border-white/10 pb-1 relative">
                            {% for d in chart_days %}
                            <div class="w-full {% if loop.last %}bg-gradient-to-t from-blue-500 to-cyan-400 rounded-sm chart-bar relative shadow-[0_0_12px_rgba(56,189,248,0.4)]{% else %}bg-gradient-to-t from-gray-200 to-gray-300 dark:from-white/10 dark:to-white/20 rounded-sm chart-bar{% endif %}" style="height: {{ d.pct if d.pct > 0 else 3 }}%"></div>
                            {% endfor %}
                        </div>
                        <div class="flex justify-between text-[9px] text-gray-400 mt-2 font-mono tracking-wider">
                            {% for d in chart_days %}
                            <span {% if loop.last %}class="text-cyan-500 font-bold"{% endif %}>{{ d.label }}</span>
                            {% endfor %}
                        </div>
                    </div>
                </div>

                <!-- سخت‌افزار -->
                <div class="glass-card p-6 rounded-3xl lg:col-span-1 flex flex-col justify-center">
                    <div class="flex justify-between items-center mb-5">
                        <h3 class="text-xs font-bold text-gray-500 dark:text-gray-400 uppercase tracking-widest" data-fa="وضعیت سخت‌افزار" data-en="Hardware Status">وضعیت سخت‌افزار</h3>
                        <i class="fa-solid fa-microchip text-gray-400"></i>
                    </div>
                    
                    <div class="flex flex-row justify-between gap-4 divide-x rtl:divide-x-reverse divide-gray-200/50 dark:divide-white/10 h-full items-center">
                        <div class="w-1/2 flex flex-col justify-center pe-2">
                            <div class="flex items-center gap-1.5 mb-2">
                                <i class="fa-solid fa-server text-amber-500 text-[10px]"></i>
                                <span class="text-[10px] text-gray-500 font-bold">CPU</span>
                            </div>
                            <span class="text-2xl font-black font-mono text-gray-900 dark:text-white mb-2">{{ hw.cpu }}<span class="text-sm text-gray-400 font-sans">%</span></span>
                            <div class="w-full bg-gray-200 dark:bg-gray-800/80 rounded-full h-1 overflow-hidden">
                                <div class="bg-gradient-to-r from-amber-400 to-orange-500 h-1 rounded-full shadow-[0_0_8px_rgba(245,158,11,0.5)]" style="width: {{ hw.cpu }}%"></div>
                            </div>
                        </div>

                        <div class="w-1/2 flex flex-col justify-center ps-4">
                            <div class="flex items-center gap-1.5 mb-2">
                                <i class="fa-solid fa-memory text-purple-500 text-[10px]"></i>
                                <span class="text-[10px] text-gray-500 font-bold">RAM</span>
                            </div>
                            <span class="text-2xl font-black font-mono text-gray-900 dark:text-white mb-2">{{ hw.ram }}<span class="text-sm text-gray-400 font-sans">%</span></span>
                            <div class="w-full bg-gray-200 dark:bg-gray-800/80 rounded-full h-1 overflow-hidden">
                                <div class="bg-gradient-to-r from-purple-500 to-indigo-500 h-1 rounded-full shadow-[0_0_8px_rgba(168,85,247,0.5)]" style="width: {{ hw.ram }}%"></div>
                            </div>
                            <p class="text-[9px] text-gray-500 font-mono mt-2">{{ hw.ram_used }} / {{ hw.ram_total }}</p>
                        </div>
                    </div>
                </div>

            </div>

            <!-- ردیف ۳: پرمصرف‌ها + IP -->
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                
                <div class="glass-card p-6 rounded-3xl flex flex-col justify-center">
                    <div class="flex justify-between items-center mb-6">
                        <h3 class="text-xs font-bold text-gray-500 dark:text-gray-400 uppercase tracking-widest" data-fa="کلاینت‌های پرمصرف" data-en="Top Traffic Clients">کلاینت‌های پرمصرف</h3>
                        <i class="fa-solid fa-trophy text-yellow-500 text-sm"></i>
                    </div>
                    
                    <div class="space-y-6">
                        {% for u in top_users %}
                        <div>
                            <div class="flex justify-between items-center mb-2">
                                <div class="flex items-center gap-2">
                                    <div class="w-5 h-5 rounded {% if loop.index == 1 %}bg-gray-100 dark:bg-white/10 flex items-center justify-center text-[10px] font-bold text-gray-900 dark:text-white{% elif loop.index == 2 %}bg-yellow-50 dark:bg-yellow-500/10 flex items-center justify-center text-[10px] text-yellow-600{% else %}bg-orange-50 dark:bg-orange-500/10 flex items-center justify-center text-[10px] text-orange-600{% endif %}">
                                        {% if loop.index == 1 %}{{ loop.index }}{% elif loop.index == 2 %}<i class="fa-solid fa-star"></i>{% else %}{{ loop.index }}{% endif %}
                                    </div>
                                    <span class="text-sm font-bold text-gray-800 dark:text-gray-200">{{ u.username }}</span>
                                </div>
                                <span class="text-[11px] font-mono font-bold text-purple-600 dark:text-purple-400">{{ u.used }}</span>
                            </div>
                            <div class="w-full bg-gray-200 dark:bg-gray-800/50 rounded-full h-1.5 overflow-hidden">
                                <div class="bg-gradient-to-r from-purple-500 to-pink-500 h-1.5 rounded-full shadow-[0_0_8px_rgba(236,72,153,0.5)]" style="width: {{ u.pct }}%"></div>
                            </div>
                        </div>
                        {% else %}
                        <p class="text-center text-gray-500 text-sm py-4">—</p>
                        {% endfor %}
                    </div>
                </div>

                <div class="glass-card p-6 rounded-3xl flex flex-col justify-center border-l-4 border-l-pink-500">
                    <div class="flex justify-between items-center mb-4">
                        <h3 class="text-xs font-bold text-gray-500 dark:text-gray-400 uppercase tracking-widest" data-fa="اسلات IP استفاده شده" data-en="IP Slots Used">اسلات IP استفاده شده</h3>
                        <i class="fa-solid fa-network-wired text-pink-500 text-sm"></i>
                    </div>
                    <div class="flex-1 flex flex-col justify-center">
                        <div class="flex justify-between items-end mb-4">
                            <span class="text-4xl font-black font-mono text-gray-900 dark:text-white">{{ total_count }} <span class="text-lg text-gray-400 font-sans">/ 240</span></span>
                            <span class="text-[10px] font-bold bg-pink-100 text-pink-600 dark:bg-pink-500/20 dark:text-pink-400 px-2 py-1 rounded">{{ ((total_count / 240) * 100) | round(1) }}% Usage</span>
                        </div>
                        <div class="w-full bg-gray-200 dark:bg-gray-800/80 rounded-full h-2 overflow-hidden mb-2">
                            <div class="bg-gradient-to-r from-pink-500 to-rose-500 h-2 rounded-full shadow-[0_0_10px_rgba(236,72,153,0.5)]" style="width: {{ ((total_count / 240) * 100) | round(1) }}%"></div>
                        </div>
                        <p class="text-[10px] text-gray-500" data-fa="ظرفیت فعلی شبکه پایدار است." data-en="Network capacity is stable.">ظرفیت فعلی شبکه پایدار است.</p>
                    </div>
                </div>

            </div>

            <!-- ردیف ۴: سرویس‌ها -->
            <div class="pt-2">
                <div class="flex justify-between items-end px-1 mb-3">
                    <h3 class="font-bold text-sm tracking-wide text-gray-800 dark:text-gray-200" data-fa="مانیتورینگ سرویس‌ها" data-en="Services Monitoring">مانیتورینگ سرویس‌ها</h3>
                </div>
                
                <div class="glass-card rounded-2xl overflow-hidden mb-10">
                    <div class="divide-y divide-gray-100 dark:divide-white/5">

                        {% set services = [
                            (svc.ocserv, 'OpenConnect', 'PORT: 555', 'fa-shield-halved', 'blue', 'سرویس در حال اجرا - بدون خطا', 'Service running - No errors'),
                            (svc.xl2tpd, 'L2TP', 'PORT: 1701', 'fa-network-wired', 'purple', 'ارتباط پایدار - رمزنگاری شده', 'Stable connection - Encrypted'),
                            (svc.ipsec, 'IPSec', 'PORT: 500', 'fa-lock', 'orange', 'تونل رمزنگاری فعال است', 'Encryption tunnel is active'),
                            (svc.nat, 'NAT', 'CORE ROUTING', 'fa-route', 'cyan', 'مسیریابی شبکه - بدون قطعی', 'Network routing - No issues'),
                            (svc.ikev2, 'IKEv2', 'PORT: 4500', 'fa-key', 'pink', 'اتصال امن - رمزنگاری قدرتمند', 'Secure connection - Strong encryption')
                        ] %}
                        {% for active, name, port, icon, color, desc_fa, desc_en in services %}
                        <div class="p-4 flex flex-col sm:flex-row sm:items-center justify-between hover:bg-white/40 dark:hover:bg-white/[0.02] transition-colors cursor-pointer group">
                            <div class="flex items-center gap-4">
                                <div class="w-10 h-10 rounded-lg bg-{{ color }}-50 dark:bg-{{ color }}-900/20 flex items-center justify-center border border-{{ color }}-100 dark:border-{{ color }}-500/20 text-{{ color }}-600 dark:text-{{ color }}-400 group-hover:scale-105 transition-transform">
                                    <i class="fa-solid {{ icon }}"></i>
                                </div>
                                <div>
                                    <div class="flex items-center gap-2">
                                        <p class="font-bold text-gray-900 dark:text-white text-sm font-mono">{{ name }}</p>
                                        <span class="px-1.5 py-0.5 bg-gray-100 dark:bg-white/10 text-gray-500 dark:text-gray-400 text-[9px] rounded font-mono border border-gray-200 dark:border-white/10">{{ port }}</span>
                                    </div>
                                    <p class="text-[11px] text-gray-500 mt-0.5" data-fa="{{ desc_fa }}" data-en="{{ desc_en }}">{{ desc_fa }}</p>
                                </div>
                            </div>
                            <div class="flex items-center justify-between sm:justify-end w-full sm:w-auto gap-4 mt-3 sm:mt-0">
                                <div class="flex items-center gap-1.5">
                                    {% if active %}
                                    <span class="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse"></span>
                                    <span class="text-[10px] font-bold text-emerald-600 dark:text-emerald-400 uppercase tracking-widest" data-fa="فعال" data-en="Active">فعال</span>
                                    {% else %}
                                    <span class="w-1.5 h-1.5 rounded-full bg-red-500"></span>
                                    <span class="text-[10px] font-bold text-red-600 dark:text-red-400 uppercase tracking-widest" data-fa="از کار افتاده" data-en="Down">از کار افتاده</span>
                                    {% endif %}
                                </div>
                                <i class="fa-solid fa-chevron-left rtl:fa-chevron-right text-gray-400 text-xs group-hover:text-gray-900 dark:group-hover:text-white transition-colors"></i>
                            </div>
                        </div>
                        {% endfor %}

                    </div>
                </div>
            </div>
        </div>
    </main>

    
<script>
        document.addEventListener("DOMContentLoaded", () => {
            const av = document.getElementById("userAvatar");
            const un = document.getElementById("usernameText");
            if(av && un) { av.innerText = un.innerText.trim().charAt(0).toUpperCase(); }
        });

        (function(){
            var t = null;
            try { t = localStorage.getItem('l2tp-theme'); } catch(e) {}
            if(!t) { t = (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches) ? 'light' : 'dark'; }
            document.documentElement.classList.toggle('dark', t !== 'light');
        })();

        function toggleTheme() {
            var html = document.documentElement;
            html.classList.toggle('dark');
            try { localStorage.setItem('l2tp-theme', html.classList.contains('dark') ? 'dark' : 'light'); } catch(e) {}
        }

        function toggleSidebar() {
            const sidebar = document.getElementById('sidebar');
            const overlay = document.getElementById('sidebarOverlay');
            overlay.classList.toggle('hidden');
            sidebar.classList.toggle('open');
        }

        // ===== Language: persistent + placeholders =====
        let currentLang = '{{ lang }}';
        function setLang(l) {
            currentLang = l;
            document.cookie = 'l2tp_lang=' + l + ';path=/;max-age=31536000';
            const html = document.documentElement;
            const btn = document.querySelector('button[onclick="toggleLanguage()"]');
            if (l === 'en') {
                html.setAttribute('dir', 'ltr');
                html.setAttribute('lang', 'en');
                if (btn) btn.innerText = 'FA';
                document.querySelectorAll('[data-en]').forEach(el => el.innerText = el.getAttribute('data-en'));
                document.querySelectorAll('input[data-en-ph]').forEach(el => el.placeholder = el.getAttribute('data-en-ph'));
            } else {
                html.setAttribute('dir', 'rtl');
                html.setAttribute('lang', 'fa');
                if (btn) btn.innerText = 'EN';
                document.querySelectorAll('[data-fa]').forEach(el => el.innerText = el.getAttribute('data-fa'));
                document.querySelectorAll('input[data-fa-ph]').forEach(el => el.placeholder = el.getAttribute('data-fa-ph'));
            }
        }
        // language handled by /lang links
        

        // ===== PSK: show/hide + copy =====
        function togglePSK() {
            var el = document.getElementById('pskText');
            if (!el) return;
            if (el.getAttribute('data-shown') === '1') {
                el.textContent = '\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022';
                el.setAttribute('data-shown', '0');
            } else {
                el.textContent = el.getAttribute('data-psk');
                el.setAttribute('data-shown', '1');
            }
        }
        function copyPSK() {
            var el = document.getElementById('pskText');
            if (!el) return;
            var psk = el.getAttribute('data-psk');
            var done = function(){ alert('PSK copied!'); };
            if (navigator.clipboard && window.isSecureContext) {
                navigator.clipboard.writeText(psk).then(done).catch(function(){
                    fallbackCopy(psk);
                });
            } else {
                fallbackCopy(psk);
            }
        }
        function fallbackCopy(text) {
            var a = document.createElement('textarea');
            a.value = text;
            a.style.position = 'fixed';
            a.style.opacity = '0';
            document.body.appendChild(a);
            a.select();
            document.execCommand('copy');
            a.remove();
            alert('PSK copied!');
        }
    
// Restore lang from COOKIE (server already rendered with it — this is just UI sync)

    </script>

<script>
// Auto-translate: سرور با lang درست رندر کرده (dir هم درسته)
// فقط متن‌های data-attr رو sync کن
(function autoTranslate(){
    var lang = document.documentElement.getAttribute('lang') || 'fa';
    if (lang === 'en') {
        document.querySelectorAll('[data-en]').forEach(function(el){
            el.innerText = el.getAttribute('data-en');
        });
        document.querySelectorAll('input[data-en-ph]').forEach(function(el){
            el.placeholder = el.getAttribute('data-en-ph');
        });
        // placeholder فارسی بدون data-attr:
        document.querySelectorAll('input[placeholder]').forEach(function(el){
            var p = el.getAttribute('placeholder');
            if (p === 'جستجو...') el.placeholder = 'Search...';
        });
        // فلش پیام‌ها:
        document.querySelectorAll('.flash-msg').forEach(function(el){
            var raw = el.getAttribute('data-msg') || el.textContent;
            var sep = raw.indexOf('|EN:');
            if (sep > -1) {
                var fa = raw.replace(/^ERR_FA:|^FA:/, '').substring(0, sep).replace(/^ERR_FA:|^FA:/,'');
                var en = raw.substring(sep + 4);
                var span = el.querySelector('.flash-text');
                if (span) span.textContent = en;
            }
        });
    }
})();
</script>
</body>
</html>

ZQ_index_html

cat > "${PANEL_DIR}/templates/user.html" <<'ZQ_user_html'
<!DOCTYPE html>
<html lang="{{ lang or 'fa' }}" dir="{{ 'ltr' if (lang or 'fa') == 'en' else 'rtl' }}" class="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>3OUTHBOY | Client Portal</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script>
        tailwind.config = { 
            darkMode: 'class',
            theme: {
                extend: {
                    colors: {
                        darkBg: '#030303',
                        darkCard: '#0c0c0c',
                        darkBorder: '#1f1f1f'
                    },
                    backgroundImage: {
                        'grid-pattern': "url('data:image/svg+xml,%3Csvg width=\\'40\\' height=\\'40\\' viewBox=\\'0 0 40 40\\' xmlns=\\'http://www.w3.org/2000/svg\\'%3E%3Cpath d=\\'M0 0h40v40H0V0zm20 20h20v20H20V20zM0 20h20v20H0V20z\\' fill=\\'%23ffffff\\' fill-opacity=\\'0.02\\' fill-rule=\\'evenodd\\'/%3E%3C/svg%3E')"
                    },
                    animation: {
                        'fade-in-up': 'fadeInUp 0.6s ease-out forwards'
                    },
                    keyframes: {
                        fadeInUp: {
                            '0%': { opacity: '0', transform: 'translateY(20px)' },
                            '100%': { opacity: '1', transform: 'translateY(0)' }
                        }
                    }
                }
            }
        }
    </script>
    <link href="https://cdn.jsdelivr.net/gh/rastikerdar/vazirmatn@v33.003/Vazirmatn-font-face.css" rel="stylesheet" />
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;700&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    
    <style>
        body { font-family: 'Vazirmatn', 'Inter', sans-serif; }
        .font-mono { font-family: 'JetBrains Mono', monospace; }
        
        ::-webkit-scrollbar { width: 5px; height: 5px; }
        ::-webkit-scrollbar-track { background: transparent; }
        ::-webkit-scrollbar-thumb { background: #333; border-radius: 10px; }
        .dark ::-webkit-scrollbar-thumb:hover { background: #555; }
        
        /* افکت‌های شیشه‌ای */
        .glass-card {
            background: rgba(255, 255, 255, 0.6);
            backdrop-filter: blur(20px);
            border: 1px solid rgba(255, 255, 255, 0.4);
            transition: all 0.3s ease;
        }
        .dark .glass-card {
            background: rgba(12, 12, 12, 0.65);
            backdrop-filter: blur(20px);
            border: 1px solid rgba(255, 255, 255, 0.08);
            box-shadow: 0 10px 40px rgba(0, 0, 0, 0.5);
        }
    </style>
</head>
<body class="bg-gray-50 dark:bg-darkBg text-gray-900 dark:text-gray-100 transition-colors duration-300 flex flex-col min-h-screen relative">

    <!-- پترن و نورهای پس‌زمینه -->
    <div class="absolute inset-0 bg-grid-pattern z-0 pointer-events-none fixed"></div>
    <div class="absolute top-0 left-0 w-full h-full overflow-hidden z-0 pointer-events-none fixed">
        <div class="absolute top-[-10%] right-[-5%] w-[300px] h-[300px] md:w-[500px] md:h-[500px] bg-purple-600/20 rounded-full blur-[100px] animate-pulse"></div>
        <div class="absolute bottom-[-10%] left-[-5%] w-[300px] h-[300px] md:w-[500px] md:h-[500px] bg-cyan-600/20 rounded-full blur-[100px] animate-pulse" style="animation-delay: 2s;"></div>
    </div>

    <!-- هدر پورتال کاربری -->
    <header class="w-full px-6 py-4 flex items-center justify-between z-30 relative border-b border-gray-200/50 dark:border-white/5 bg-white/30 dark:bg-black/20 backdrop-blur-md">
        <div class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-xl bg-gradient-to-br from-purple-600 to-cyan-600 flex items-center justify-center shadow-lg border border-gray-700 dark:border-gray-100">
                <span class="text-white font-black text-xl font-sans tracking-tighter">3</span>
            </div>
            <div class="flex flex-col">
                <span class="font-bold tracking-widest bg-clip-text text-transparent bg-gradient-to-r from-purple-500 to-cyan-500 text-lg">3OUTHBOY</span>
                <span class="text-[9px] text-gray-500 font-mono tracking-widest">CLIENT PORTAL</span>
            </div>
        </div>
        
        <div class="flex items-center gap-2">
            <button onclick="toggleLanguage()" class="w-9 h-9 rounded-xl bg-gray-100 dark:bg-white/5 border border-gray-200 dark:border-white/10 flex items-center justify-center hover:bg-gray-200 dark:hover:bg-white/10 transition-all font-bold text-[10px] shadow-sm font-mono">EN</button>
            <button onclick="toggleTheme()" id="theme-icon" class="w-9 h-9 rounded-xl bg-gray-100 dark:bg-white/5 border border-gray-200 dark:border-white/10 flex items-center justify-center hover:bg-gray-200 dark:hover:bg-white/10 transition-all text-gray-600 dark:text-gray-300 shadow-sm">
                <i class="fa-solid fa-sun text-sm"></i>
            </button>
        </div>
    </header>

    <!-- محتوای اصلی -->
    <main class="flex-1 w-full max-w-3xl mx-auto px-4 py-8 z-10 relative space-y-6 animate-fade-in-up">
        
        <!-- کارت وضعیت سرویس -->
        <div class="glass-card rounded-[2rem] p-6 sm:p-8 relative overflow-hidden">
            <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-8">
                <div class="flex items-center gap-4">
                    <div class="w-14 h-14 rounded-2xl bg-gradient-to-br from-gray-100 to-gray-200 dark:from-white/10 dark:to-white/5 flex items-center justify-center text-gray-800 dark:text-white border border-gray-300 dark:border-white/10 shadow-inner text-2xl font-bold font-sans">
                        {{ u.username[0]|upper }}
                    </div>
                    <div>
                        <h2 class="text-xl font-bold text-gray-900 dark:text-white flex items-center gap-2">
                            <span data-fa="سلام،" data-en="Hello,">سلام،</span> {{ u.username }}
                        </h2>
                        <div class="flex items-center gap-1.5 mt-1">
                            <span class="w-2 h-2 {{ 'bg-red-500' if u.expired else ('bg-orange-500' if u.quota_exceeded else 'bg-emerald-500 rounded-full animate-pulse shadow-[0_0_8px_rgba(16,185,129,0.8)]') }} rounded-full"></span>
                            {% if u.expired %}
                            <span class="text-xs text-red-600 dark:text-red-400 font-bold tracking-wider uppercase" data-fa="سرویس منقضی شده است" data-en="Service Expired">سرویس منقضی شده است</span>
                            {% elif u.quota_exceeded %}
                            <span class="text-xs text-orange-600 dark:text-orange-400 font-bold tracking-wider uppercase" data-fa="حجم سرویس به پایان رسیده" data-en="Quota Exhausted">حجم سرویس به پایان رسیده</span>
                            {% else %}
                            <span id="protocol-status-badge" class="text-xs text-emerald-600 dark:text-emerald-400 font-bold tracking-wider uppercase" data-fa="سرویس مولتی فعال است" data-en="Multi Service Active">سرویس مولتی فعال است</span>
                            {% endif %}
                        </div>
                    </div>
                </div>
                <div class="text-start sm:text-end">
                    <p class="text-[10px] text-gray-500 font-bold uppercase tracking-widest mb-1" data-fa="انقضا سرویس" data-en="Expiration Date">انقضا سرویس</p>
                    <p class="text-lg font-bold font-mono text-gray-900 dark:text-white">{{ u.expires[:10]|replace('-', '/') }}</p>
                    {% if u.remaining and u.remaining != '—' %}
                    <p class="text-xs text-orange-500 mt-0.5 font-bold">{{ u.remaining }}</p>
                    {% endif %}
                </div>
            </div>

            <!-- نمودار ترافیک -->
            <div class="bg-gray-50 dark:bg-black/30 p-5 rounded-2xl border border-gray-200/50 dark:border-white/5">
                <div class="flex justify-between items-end mb-3">
                    <div>
                        <p class="text-[10px] text-gray-500 font-bold uppercase tracking-widest mb-1" data-fa="ترافیک مصرفی" data-en="Data Usage">ترافیک مصرفی</p>
                        <p class="text-2xl font-black font-mono tracking-tighter text-transparent bg-clip-text bg-gradient-to-r from-purple-500 to-cyan-500">{{ used_gb }} <span class="text-sm text-gray-500 font-bold ml-1">GB</span></p>
                    </div>
                    <div class="text-end">
                        <p class="text-[10px] text-gray-500 font-bold uppercase tracking-widest mb-1" data-fa="ترافیک کل" data-en="Total Quota">ترافیک کل</p>
                        {% if u.limit_gb > 0 %}
                        <p class="text-lg font-bold font-mono text-gray-700 dark:text-gray-300">{{ u.limit_gb }} <span class="text-xs">GB</span></p>
                        {% else %}
                        <p class="text-lg font-bold font-mono text-gray-700 dark:text-gray-300">∞</p>
                        {% endif %}
                    </div>
                </div>
                <div class="w-full bg-gray-200 dark:bg-gray-800 rounded-full h-2.5 overflow-hidden">
                    <div class="bg-gradient-to-r from-purple-500 via-cyan-500 to-blue-500 h-2.5 rounded-full shadow-[0_0_10px_rgba(6,182,212,0.5)]" style="width: {{ u.traffic_pct if u.limit_gb > 0 else 100 }}%"></div>
                </div>
                <div class="flex justify-between mt-2">
                    <span class="text-[10px] text-gray-500 font-mono">{% if u.limit_gb > 0 %}{{ u.traffic_pct }}% Used{% else %}Unlimited{% endif %}</span>
                    {% if u.limit_gb > 0 and not u.quota_exceeded %}
                    <span class="text-[10px] text-cyan-600 dark:text-cyan-400 font-bold" data-fa="{{ left_gb }} گیگابایت باقی‌مانده" data-en="{{ left_gb }} GB Remaining">{{ left_gb }} گیگابایت باقی‌مانده</span>
                    {% endif %}
                </div>
            </div>
        </div>

        <!-- کلید رمزنگاری شما -->
        <div class="glass-card rounded-[2rem] p-6 sm:p-8 bg-gradient-to-br from-purple-500/5 to-cyan-500/5 border-purple-500/20 dark:border-cyan-500/20">
            <h3 class="text-sm font-bold text-gray-900 dark:text-white mb-4" data-fa="لینک ساب" data-en="Sub Link">لینک ساب</h3>
            
            <div class="flex flex-col sm:flex-row gap-3">
                <div class="relative flex-1 group">
                    <div class="absolute inset-y-0 start-0 flex items-center ps-4 pointer-events-none text-cyan-500"><i class="fa-solid fa-key"></i></div>
                    <input type="text" id="subLink" value="{{ request.url_root }}u/{{ u.key }}" class="bg-white dark:bg-black/40 border border-gray-200 dark:border-white/10 text-sm sm:text-base rounded-xl block w-full ps-11 p-3.5 text-gray-900 dark:text-white outline-none font-mono tracking-wide" readonly>
                </div>
                <div class="flex gap-2">
                    <button onclick="copyToClipboard('subLink', this)" class="flex-1 sm:flex-none px-6 py-3.5 rounded-xl bg-gradient-to-r from-purple-600 to-cyan-600 hover:from-purple-500 hover:to-cyan-500 text-white font-bold shadow-[0_5px_20px_rgba(168,85,247,0.4)] transition-all flex items-center justify-center gap-2">
                        <i class="fa-regular fa-copy"></i> <span class="copy-text" data-fa="کپی کلید" data-en="Copy Key">کپی کلید</span>
                    </button>
                    <button onclick="toggleModal('qrModal')" class="px-4 py-3.5 rounded-xl bg-gray-100 dark:bg-white/10 hover:bg-gray-200 dark:hover:bg-white/20 text-gray-700 dark:text-white border border-gray-200 dark:border-white/10 transition-all flex items-center justify-center tooltip" title="نمایش بارکد (QR)">
                        <i class="fa-solid fa-qrcode text-lg"></i>
                    </button>
                </div>
            </div>
            <div class="mt-4 flex items-start gap-2 p-3 rounded-xl bg-orange-50 dark:bg-orange-500/10 border border-orange-200 dark:border-orange-500/20">
                <i class="fa-solid fa-triangle-exclamation text-orange-500 mt-0.5 text-xs"></i>
                <p class="text-[10px] sm:text-xs text-orange-700 dark:text-orange-400 leading-relaxed" data-fa="هشدار: این لینک ساب اختصاصی شماست. از پخش و اشتراک‌گذاری آن با دیگران خودداری کنید، در غیر این صورت سرویس شما مسدود خواهد شد." data-en="Warning: This is your private subscription link. Do not share or distribute it, otherwise your account will be suspended.">هشدار: این لینک ساب اختصاصی شماست. از پخش و اشتراک‌گذاری آن با دیگران خودداری کنید، در غیر این صورت سرویس شما مسدود خواهد شد.</p>
            </div>
        </div>

        <!-- کانفیگ‌های دستی / سرورها -->
        <div>
            <h3 class="font-bold text-sm text-gray-800 dark:text-gray-200 mb-4 px-2" data-fa="کانفیگ‌های دستی (در صورت نیاز)" data-en="Manual Configurations (Optional)">کانفیگ‌های دستی (در صورت نیاز)</h3>
            <div class="glass-card rounded-[1.5rem] overflow-hidden">
                <div class="divide-y divide-gray-100 dark:divide-white/5">
                    
                    <!-- OpenConnect Box -->
                    <div id="config-openconnect" class="p-4 sm:p-5 flex flex-col gap-4 hover:bg-white/40 dark:hover:bg-white/[0.02] transition-colors group">
                        <div class="flex items-center gap-3">
                            <div class="w-8 h-8 rounded-lg bg-blue-50 dark:bg-blue-500/10 flex items-center justify-center border border-blue-100 dark:border-blue-500/20 text-blue-600 dark:text-blue-400"><i class="fa-solid fa-shield-halved text-xs"></i></div>
                            <h4 class="font-bold text-gray-900 dark:text-white text-sm font-mono tracking-wide">OpenConnect (Cisco)</h4>
                        </div>
                        
                        <div class="grid grid-cols-1 sm:grid-cols-3 gap-2 sm:gap-3 bg-gray-50/50 dark:bg-black/20 p-3 rounded-xl border border-gray-200/50 dark:border-white/5">
                            <div class="flex items-center justify-between bg-white dark:bg-white/5 p-2.5 rounded-lg border border-gray-200 dark:border-white/5">
                                <div class="flex flex-col">
                                    <span class="text-[9px] text-gray-400 uppercase tracking-widest" data-fa="آدرس سرور" data-en="Server Address">آدرس سرور</span>
                                    <span class="text-xs font-mono text-gray-900 dark:text-gray-100 font-bold mt-0.5" id="oc-server">{{ server_ip }}{% if oc_tcp %}:{{ oc_tcp }}{% endif %}</span>
                                </div>
                                <button onclick="copyToClipboard('oc-server', this, true)" class="w-7 h-7 rounded bg-gray-100 dark:bg-white/10 flex items-center justify-center text-gray-500 hover:text-blue-500 transition-colors">
                                    <i class="fa-regular fa-copy text-[10px]"></i>
                                </button>
                            </div>
                            <div class="flex items-center justify-between bg-white dark:bg-white/5 p-2.5 rounded-lg border border-gray-200 dark:border-white/5">
                                <div class="flex flex-col">
                                    <span class="text-[9px] text-gray-400 uppercase tracking-widest" data-fa="نام کاربری" data-en="Username">نام کاربری</span>
                                    <span class="text-xs font-mono text-gray-900 dark:text-gray-100 font-bold mt-0.5" id="oc-user">{{ u.username }}</span>
                                </div>
                                <button onclick="copyToClipboard('oc-user', this, true)" class="w-7 h-7 rounded bg-gray-100 dark:bg-white/10 flex items-center justify-center text-gray-500 hover:text-blue-500 transition-colors">
                                    <i class="fa-regular fa-copy text-[10px]"></i>
                                </button>
                            </div>
                            <div class="flex items-center justify-between bg-white dark:bg-white/5 p-2.5 rounded-lg border border-gray-200 dark:border-white/5">
                                <div class="flex flex-col">
                                    <span class="text-[9px] text-gray-400 uppercase tracking-widest" data-fa="رمز عبور" data-en="Password">رمز عبور</span>
                                    <span class="text-xs font-mono text-gray-900 dark:text-gray-100 font-bold mt-0.5" id="oc-pass">{{ u.password }}</span>
                                </div>
                                <button onclick="copyToClipboard('oc-pass', this, true)" class="w-7 h-7 rounded bg-gray-100 dark:bg-white/10 flex items-center justify-center text-gray-500 hover:text-blue-500 transition-colors">
                                    <i class="fa-regular fa-copy text-[10px]"></i>
                                </button>
                            </div>
                        </div>
                    </div>

                    <!-- L2TP / IPSec Box -->
                    <div id="config-l2tp" class="p-4 sm:p-5 flex flex-col gap-4 hover:bg-white/40 dark:hover:bg-white/[0.02] transition-colors group">
                        <div class="flex items-center gap-3">
                            <div class="w-8 h-8 rounded-lg bg-orange-50 dark:bg-orange-500/10 flex items-center justify-center border border-orange-100 dark:border-orange-500/20 text-orange-600 dark:text-orange-400"><i class="fa-solid fa-lock text-xs"></i></div>
                            <h4 class="font-bold text-gray-900 dark:text-white text-sm font-mono tracking-wide">L2TP / IPSec</h4>
                        </div>
                        
                        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-2 sm:gap-3 bg-gray-50/50 dark:bg-black/20 p-3 rounded-xl border border-gray-200/50 dark:border-white/5">
                            <div class="flex items-center justify-between bg-white dark:bg-white/5 p-2.5 rounded-lg border border-gray-200 dark:border-white/5">
                                <div class="flex flex-col">
                                    <span class="text-[9px] text-gray-400 uppercase tracking-widest" data-fa="آدرس سرور" data-en="Server Address">آدرس سرور</span>
                                    <span class="text-xs font-mono text-gray-900 dark:text-gray-100 font-bold mt-0.5" id="l2tp-server">{{ server_ip }}</span>
                                </div>
                                <button onclick="copyToClipboard('l2tp-server', this, true)" class="w-7 h-7 rounded bg-gray-100 dark:bg-white/10 flex items-center justify-center text-gray-500 hover:text-orange-500 transition-colors">
                                    <i class="fa-regular fa-copy text-[10px]"></i>
                                </button>
                            </div>
                            <div class="flex items-center justify-between bg-white dark:bg-white/5 p-2.5 rounded-lg border border-gray-200 dark:border-white/5">
                                <div class="flex flex-col">
                                    <span class="text-[9px] text-gray-400 uppercase tracking-widest" data-fa="نام کاربری" data-en="Username">نام کاربری</span>
                                    <span class="text-xs font-mono text-gray-900 dark:text-gray-100 font-bold mt-0.5" id="l2tp-user">{{ u.username }}</span>
                                </div>
                                <button onclick="copyToClipboard('l2tp-user', this, true)" class="w-7 h-7 rounded bg-gray-100 dark:bg-white/10 flex items-center justify-center text-gray-500 hover:text-orange-500 transition-colors">
                                    <i class="fa-regular fa-copy text-[10px]"></i>
                                </button>
                            </div>
                            <div class="flex items-center justify-between bg-white dark:bg-white/5 p-2.5 rounded-lg border border-gray-200 dark:border-white/5">
                                <div class="flex flex-col">
                                    <span class="text-[9px] text-gray-400 uppercase tracking-widest" data-fa="رمز عبور" data-en="Password">رمز عبور</span>
                                    <span class="text-xs font-mono text-gray-900 dark:text-gray-100 font-bold mt-0.5" id="l2tp-pass">{{ u.password }}</span>
                                </div>
                                <button onclick="copyToClipboard('l2tp-pass', this, true)" class="w-7 h-7 rounded bg-gray-100 dark:bg-white/10 flex items-center justify-center text-gray-500 hover:text-orange-500 transition-colors">
                                    <i class="fa-regular fa-copy text-[10px]"></i>
                                </button>
                            </div>
                            <div class="flex items-center justify-between bg-white dark:bg-white/5 p-2.5 rounded-lg border border-gray-200 dark:border-white/5">
                                <div class="flex flex-col w-[80%]">
                                    <span class="text-[9px] text-gray-400 uppercase tracking-widest" data-fa="کلید مشترک (Secret)" data-en="IPSec Pre-Shared Key">کلید مشترک (Secret)</span>
                                    <span class="text-xs font-mono text-orange-600 dark:text-orange-400 font-bold mt-0.5 truncate" id="ipsec-secret">{{ psk }}</span>
                                </div>
                                <button onclick="copyToClipboard('ipsec-secret', this, true)" class="w-7 h-7 rounded bg-gray-100 dark:bg-white/10 flex items-center justify-center text-gray-500 hover:text-orange-500 transition-colors">
                                    <i class="fa-regular fa-copy text-[10px]"></i>
                                </button>
                            </div>
                        </div>
                    </div>

                </div>
            </div>
        </div>

        <!-- اپلیکیشن‌های مورد نیاز -->
        <div id="apps-section">
            <h3 class="font-bold text-sm text-gray-800 dark:text-gray-200 mb-4 px-2" data-fa="دانلود نرم‌افزارهای اتصال" data-en="Download Client Apps">دانلود نرم‌افزارهای اتصال</h3>
            <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
                <!-- دکمه اندروید -->
                <button type="button" onclick="toggleModal('dlModalAndroid')" class="w-full glass-card p-4 rounded-2xl flex flex-col items-center justify-center text-center hover:bg-white/20 dark:hover:bg-white/5 transition-all group">
                    <i class="fa-brands fa-android text-3xl text-emerald-500 mb-2 group-hover:scale-110 transition-transform"></i>
                    <span class="text-xs font-bold text-gray-800 dark:text-gray-200">Android</span>
                    <span class="text-[10px] text-gray-500 mt-1 font-mono tracking-wide">OpenConnect</span>
                </button>
                <!-- دکمه آی‌او‌اس -->
                <button type="button" onclick="toggleModal('dlModalIOS')" class="w-full glass-card p-4 rounded-2xl flex flex-col items-center justify-center text-center hover:bg-white/20 dark:hover:bg-white/5 transition-all group">
                    <i class="fa-brands fa-apple text-3xl text-gray-800 dark:text-white mb-2 group-hover:scale-110 transition-transform"></i>
                    <span class="text-xs font-bold text-gray-800 dark:text-gray-200">iOS</span>
                    <span class="text-[10px] text-gray-500 mt-1 font-mono tracking-wide">Cisco Secure Client</span>
                </button>
                <!-- دکمه ویندوز -->
                <button type="button" onclick="toggleModal('dlModalWindows')" class="w-full glass-card p-4 rounded-2xl flex flex-col items-center justify-center text-center hover:bg-white/20 dark:hover:bg-white/5 transition-all group">
                    <i class="fa-brands fa-windows text-3xl text-blue-500 mb-2 group-hover:scale-110 transition-transform"></i>
                    <span class="text-xs font-bold text-gray-800 dark:text-gray-200">Windows</span>
                    <span class="text-[10px] text-gray-500 mt-1 font-mono tracking-wide">OpenConnect</span>
                </button>
                <!-- دکمه مک -->
                <button type="button" onclick="toggleModal('dlModalMac')" class="w-full glass-card p-4 rounded-2xl flex flex-col items-center justify-center text-center hover:bg-white/20 dark:hover:bg-white/5 transition-all group">
                    <i class="fa-brands fa-apple text-3xl text-gray-800 dark:text-white mb-2 group-hover:scale-110 transition-transform"></i>
                    <span class="text-xs font-bold text-gray-800 dark:text-gray-200">Mac OS</span>
                    <span class="text-[10px] text-gray-500 mt-1 font-mono tracking-wide">Cisco Secure Client</span>
                </button>
            </div>
        </div>

    </main>

    <!-- فوتر -->
    <footer class="w-full text-center py-6 mt-auto z-10 relative">
        <p class="text-[10px] text-gray-400 font-mono">Secured by 3OUTHBOY Network &copy; 2026</p>
    </footer>

    <!-- ================= MODAL نمایش QR Code ================= -->
    <div id="qrModal" class="fixed inset-0 z-[100] hidden items-center justify-center opacity-0 transition-opacity duration-300 px-4">
        <div class="absolute inset-0 bg-black/80 backdrop-blur-sm" onclick="toggleModal('qrModal')"></div>
        <div class="glass-card relative w-full max-w-sm rounded-[2rem] p-8 shadow-[0_20px_50px_rgba(0,0,0,0.5)] transform scale-95 transition-transform duration-300 z-10 text-center border-t border-t-white/20">
            <button onclick="toggleModal('qrModal')" class="absolute top-4 end-4 w-8 h-8 rounded-full bg-gray-100 dark:bg-white/10 flex items-center justify-center text-gray-500 hover:text-white transition-colors">
                <i class="fa-solid fa-xmark"></i>
            </button>
            <h3 class="text-lg font-bold text-gray-900 dark:text-white mb-1" data-fa="بارکد اتصال (QR Code)" data-en="Connection QR Code">بارکد اتصال (QR Code)</h3>
            <p class="text-xs text-gray-500 mb-6" data-fa="با دوربین گوشی خود اسکن کنید" data-en="Scan with your phone camera">با دوربین گوشی خود اسکن کنید</p>
            <div class="bg-white p-4 rounded-2xl mx-auto w-fit shadow-lg mb-6">
                <img src="https://api.qrserver.com/v1/create-qr-code/?size=200x200&data={{ (request.url_root ~ 'u/' ~ u.key)|urlencode }}&color=000000&bgcolor=ffffff" alt="QR Code" class="w-48 h-48 rounded-lg">
            </div>
            <p class="text-[10px] text-orange-500 font-bold" data-fa="لطفاً این بارکد را به هیچ‌کس نشان ندهید." data-en="Please do not show this barcode to anyone.">لطفاً این بارکد را به هیچ‌کس نشان ندهید.</p>
        </div>
    </div>

    <!-- ================= MODAL اندروید ================= -->
    <div id="dlModalAndroid" class="fixed inset-0 z-[100] hidden items-center justify-center opacity-0 transition-opacity duration-300 px-4">
        <div class="absolute inset-0 bg-black/80 backdrop-blur-sm" onclick="toggleModal('dlModalAndroid')"></div>
        <div class="glass-card relative w-full max-w-sm rounded-[2rem] p-8 shadow-[0_20px_50px_rgba(0,0,0,0.5)] transform scale-95 transition-transform duration-300 z-10 text-center border-t border-t-white/20">
            <div class="w-16 h-16 rounded-full bg-emerald-50 dark:bg-emerald-500/10 flex items-center justify-center mx-auto mb-4 border border-emerald-100 dark:border-emerald-500/20">
                <i class="fa-brands fa-google-play text-2xl text-emerald-500"></i>
            </div>
            <h3 class="text-lg font-bold text-gray-900 dark:text-white mb-2" data-fa="دانلود OpenConnect" data-en="Download OpenConnect">دانلود OpenConnect</h3>
            <p class="text-[13px] text-gray-500 mb-8 leading-relaxed" data-fa="آیا می‌خواهید برای دانلود این برنامه به فروشگاه گوگل پلی (Google Play) منتقل شوید؟" data-en="Do you want to be redirected to Google Play Store to download the app?">آیا می‌خواهید برای دانلود این برنامه به فروشگاه گوگل پلی (Google Play) منتقل شوید؟</p>
            <div class="flex gap-3">
                <button onclick="toggleModal('dlModalAndroid')" class="flex-1 px-4 py-3 rounded-xl bg-gray-100 dark:bg-white/10 hover:bg-gray-200 dark:hover:bg-white/20 text-gray-700 dark:text-white font-bold transition-all text-sm border border-gray-200 dark:border-white/10" data-fa="خیر، انصراف" data-en="No, Cancel">خیر، انصراف</button>
                <a href="https://play.google.com/store/apps/details?id=com.github.digitalsoftwaresolutions.openconnect" target="_blank" onclick="toggleModal('dlModalAndroid')" class="flex-1 px-4 py-3 rounded-xl bg-gradient-to-r from-emerald-500 to-teal-500 hover:from-emerald-400 hover:to-teal-400 text-white font-bold shadow-[0_5px_15px_rgba(16,185,129,0.3)] transition-all text-sm flex items-center justify-center gap-2">
                    <span data-fa="بله، دانلود" data-en="Yes, Download">بله، دانلود</span>
                </a>
            </div>
        </div>
    </div>

    <!-- ================= MODAL آی‌او‌اس ================= -->
    <div id="dlModalIOS" class="fixed inset-0 z-[100] hidden items-center justify-center opacity-0 transition-opacity duration-300 px-4">
        <div class="absolute inset-0 bg-black/80 backdrop-blur-sm" onclick="toggleModal('dlModalIOS')"></div>
        <div class="glass-card relative w-full max-w-sm rounded-[2rem] p-8 shadow-[0_20px_50px_rgba(0,0,0,0.5)] transform scale-95 transition-transform duration-300 z-10 text-center border-t border-t-white/20">
            <div class="w-16 h-16 rounded-full bg-blue-50 dark:bg-blue-500/10 flex items-center justify-center mx-auto mb-4 border border-blue-100 dark:border-blue-500/20">
                <i class="fa-brands fa-app-store-ios text-2xl text-blue-500"></i>
            </div>
            <h3 class="text-lg font-bold text-gray-900 dark:text-white mb-2" data-fa="دانلود Cisco Secure Client" data-en="Download Cisco Secure Client">دانلود Cisco Secure Client</h3>
            <p class="text-[13px] text-gray-500 mb-8 leading-relaxed" data-fa="آیا می‌خواهید برای دانلود این برنامه به اپ استور (App Store) منتقل شوید؟" data-en="Do you want to be redirected to the App Store to download this app?">آیا می‌خواهید برای دانلود این برنامه به اپ استور (App Store) منتقل شوید؟</p>
            <div class="flex gap-3">
                <button onclick="toggleModal('dlModalIOS')" class="flex-1 px-4 py-3 rounded-xl bg-gray-100 dark:bg-white/10 hover:bg-gray-200 dark:hover:bg-white/20 text-gray-700 dark:text-white font-bold transition-all text-sm border border-gray-200 dark:border-white/10" data-fa="خیر، انصراف" data-en="No, Cancel">خیر، انصراف</button>
                <a href="https://apps.apple.com/us/app/cisco-secure-client/id1135064690" target="_blank" onclick="toggleModal('dlModalIOS')" class="flex-1 px-4 py-3 rounded-xl bg-gradient-to-r from-blue-500 to-cyan-500 hover:from-blue-400 hover:to-cyan-400 text-white font-bold shadow-[0_5px_15px_rgba(59,130,246,0.3)] transition-all text-sm flex items-center justify-center gap-2">
                    <span data-fa="بله، دانلود" data-en="Yes, Download">بله، دانلود</span>
                </a>
            </div>
        </div>
    </div>

    <!-- ================= MODAL ویندوز ================= -->
    <div id="dlModalWindows" class="fixed inset-0 z-[100] hidden items-center justify-center opacity-0 transition-opacity duration-300 px-4">
        <div class="absolute inset-0 bg-black/80 backdrop-blur-sm" onclick="toggleModal('dlModalWindows')"></div>
        <div class="glass-card relative w-full max-w-sm rounded-[2rem] p-8 shadow-[0_20px_50px_rgba(0,0,0,0.5)] transform scale-95 transition-transform duration-300 z-10 text-center border-t border-t-white/20">
            <div class="w-16 h-16 rounded-full bg-cyan-50 dark:bg-cyan-500/10 flex items-center justify-center mx-auto mb-4 border border-cyan-100 dark:border-cyan-500/20">
                <i class="fa-brands fa-windows text-2xl text-cyan-500"></i>
            </div>
            <h3 class="text-lg font-bold text-gray-900 dark:text-white mb-2" data-fa="دانلود OpenConnect GUI" data-en="Download OpenConnect GUI">دانلود OpenConnect GUI</h3>
            <p class="text-[13px] text-gray-500 mb-8 leading-relaxed" data-fa="آیا می‌خواهید فایل نصبی (exe) این برنامه را به صورت مستقیم دانلود کنید؟" data-en="Do you want to directly download the installation file (exe) for this app?">آیا می‌خواهید فایل نصبی (exe) این برنامه را به صورت مستقیم دانلود کنید؟</p>
            <div class="flex gap-3">
                <button onclick="toggleModal('dlModalWindows')" class="flex-1 px-4 py-3 rounded-xl bg-gray-100 dark:bg-white/10 hover:bg-gray-200 dark:hover:bg-white/20 text-gray-700 dark:text-white font-bold transition-all text-sm border border-gray-200 dark:border-white/10" data-fa="خیر، انصراف" data-en="No, Cancel">خیر، انصراف</button>
                <a href="https://www.infradead.org/openconnect-gui/download/openconnect-gui-1.6.2-win64.exe" onclick="toggleModal('dlModalWindows')" class="flex-1 px-4 py-3 rounded-xl bg-gradient-to-r from-cyan-500 to-blue-500 hover:from-cyan-400 hover:to-blue-400 text-white font-bold shadow-[0_5px_15px_rgba(6,182,212,0.3)] transition-all text-sm flex items-center justify-center gap-2">
                    <span data-fa="بله، دانلود" data-en="Yes, Download">بله، دانلود</span>
                </a>
            </div>
        </div>
    </div>

    <!-- ================= MODAL مک ================= -->
    <div id="dlModalMac" class="fixed inset-0 z-[100] hidden items-center justify-center opacity-0 transition-opacity duration-300 px-4">
        <div class="absolute inset-0 bg-black/80 backdrop-blur-sm" onclick="toggleModal('dlModalMac')"></div>
        <div class="glass-card relative w-full max-w-sm rounded-[2rem] p-8 shadow-[0_20px_50px_rgba(0,0,0,0.5)] transform scale-95 transition-transform duration-300 z-10 text-center border-t border-t-white/20">
            <div class="w-16 h-16 rounded-full bg-gray-100 dark:bg-white/5 flex items-center justify-center mx-auto mb-4 border border-gray-200 dark:border-white/10">
                <i class="fa-brands fa-apple text-2xl text-gray-800 dark:text-white"></i>
            </div>
            <h3 class="text-lg font-bold text-gray-900 dark:text-white mb-2" data-fa="دانلود Cisco Secure Client" data-en="Download Cisco Secure Client">دانلود Cisco Secure Client</h3>
            <p class="text-[13px] text-gray-500 mb-8 leading-relaxed" data-fa="آیا می‌خواهید برای دریافت این برنامه به وب‌سایت رسمی سیسکو منتقل شوید؟" data-en="Do you want to be redirected to the official Cisco website to get this app?">آیا می‌خواهید برای دریافت این برنامه به وب‌سایت رسمی سیسکو منتقل شوید؟</p>
            <div class="flex gap-3">
                <button onclick="toggleModal('dlModalMac')" class="flex-1 px-4 py-3 rounded-xl bg-gray-100 dark:bg-white/10 hover:bg-gray-200 dark:hover:bg-white/20 text-gray-700 dark:text-white font-bold transition-all text-sm border border-gray-200 dark:border-white/10" data-fa="خیر، انصراف" data-en="No, Cancel">خیر، انصراف</button>
                <a href="https://software.cisco.com/download/home/286330811/type/282364313/release/5.1.20.333" target="_blank" onclick="toggleModal('dlModalMac')" class="flex-1 px-4 py-3 rounded-xl bg-gradient-to-r from-gray-700 to-gray-900 dark:from-gray-600 dark:to-gray-800 hover:opacity-90 text-white font-bold shadow-[0_5px_15px_rgba(0,0,0,0.3)] transition-all text-sm flex items-center justify-center gap-2">
                    <span data-fa="بله، دانلود" data-en="Yes, Download">بله، دانلود</span>
                </a>
            </div>
        </div>
    </div>

    <script>
        // ==========================================
        // تنظیمات داینامیک پروتکل کاربر (از سرور)
        // ==========================================
        const CLIENT_PROTOCOL = '{{ 'multi' if u.protocol in ('all', 'ikev2') else u.protocol }}';
        const USER_STATE = '{{ 'expired' if u.expired else ('quota' if u.quota_exceeded else 'active') }}';

        document.addEventListener("DOMContentLoaded", () => {
            applySavedLang();
            applyProtocolView(CLIENT_PROTOCOL);
        });

        // اعمال زبان ذخیره‌شده کاربر (localStorage)
        function applySavedLang() {
            if (localStorage.getItem('portal_lang') === 'en') {
                const html = document.documentElement;
                const btn = document.querySelector('button[onclick="toggleLanguage()"]');
                html.setAttribute('dir', 'ltr');
                html.setAttribute('lang', 'en');
                if (btn) btn.innerText = 'FA';
                document.querySelectorAll('[data-en]').forEach(el => el.innerText = el.getAttribute('data-en'));
            }
        }

        // تابع مدیریت نمایش پروتکل‌ها بر اساس کانفیگ کاربر
        function applyProtocolView(protocol) {
            const statusBadge = document.getElementById('protocol-status-badge');
            const ocConfig = document.getElementById('config-openconnect');
            const l2tpConfig = document.getElementById('config-l2tp');
            const isEn = document.documentElement.getAttribute('lang') === 'en';

            ocConfig.classList.remove('hidden');
            l2tpConfig.classList.remove('hidden');
            ocConfig.classList.add('flex');
            l2tpConfig.classList.add('flex');

            if (protocol === 'openconnect') {
                l2tpConfig.classList.add('hidden');
                l2tpConfig.classList.remove('flex');
            } 
            else if (protocol === 'l2tp') {
                ocConfig.classList.add('hidden');
                ocConfig.classList.remove('flex');
            }

            // بج وضعیت فقط برای کاربران فعال توسط JS مدیریت می‌شود
            if (USER_STATE !== 'active' || !statusBadge) return;

            if (protocol === 'openconnect') {
                statusBadge.setAttribute('data-fa', 'سرویس OpenConnect فعال است');
                statusBadge.setAttribute('data-en', 'OpenConnect Active');
                statusBadge.innerText = isEn ? 'OpenConnect Active' : 'سرویس OpenConnect فعال است';
            } 
            else if (protocol === 'l2tp') {
                statusBadge.setAttribute('data-fa', 'سرویس L2TP فعال است');
                statusBadge.setAttribute('data-en', 'L2TP Service Active');
                statusBadge.innerText = isEn ? 'L2TP Service Active' : 'سرویس L2TP فعال است';
            }
        }

        // تابع تغییر تم
        function toggleTheme() {
            const html = document.documentElement;
            const icon = document.querySelector('#theme-icon i');
            html.classList.toggle('dark');
            if (html.classList.contains('dark')) {
                icon.classList.replace('fa-moon', 'fa-sun');
            } else {
                icon.classList.replace('fa-sun', 'fa-moon');
            }
        }

        // تابع تغییر زبان
        function toggleLanguage() {
            const html = document.documentElement;
            const btn = document.querySelector('button[onclick="toggleLanguage()"]');
            
            if (html.getAttribute('lang') === 'fa') {
                html.setAttribute('dir', 'ltr');
                html.setAttribute('lang', 'en');
                btn.innerText = 'FA';
                localStorage.setItem('portal_lang', 'en');
                document.querySelectorAll('[data-en]').forEach(el => el.innerText = el.getAttribute('data-en'));
            } else {
                html.setAttribute('dir', 'rtl');
                html.setAttribute('lang', 'fa');
                btn.innerText = 'EN';
                localStorage.setItem('portal_lang', 'fa');
                document.querySelectorAll('[data-fa]').forEach(el => el.innerText = el.getAttribute('data-fa'));
            }
        }

        // تابع کپی با انیمیشن
        function copyToClipboard(elementId, btnElement, isTextElement = false) {
            let copyText;
            if(isTextElement){
                copyText = document.getElementById(elementId).innerText;
            } else {
                copyText = document.getElementById(elementId).value;
            }

            navigator.clipboard.writeText(copyText).then(() => {
                const textSpan = btnElement.querySelector('.copy-text');
                const icon = btnElement.querySelector('i');
                const originalIcon = icon.className;

                if(textSpan) {
                    const originalText = textSpan.innerText;
                    const isEn = document.documentElement.getAttribute('lang') === 'en';
                    textSpan.innerText = isEn ? 'Copied!' : 'کپی شد!';
                    icon.className = 'fa-solid fa-check text-emerald-500';
                    btnElement.classList.add('ring-2', 'ring-emerald-500', 'ring-offset-2', 'dark:ring-offset-[#0c0c0c]');

                    setTimeout(() => {
                        textSpan.innerText = originalText;
                        icon.className = originalIcon;
                        btnElement.classList.remove('ring-2', 'ring-emerald-500', 'ring-offset-2', 'dark:ring-offset-[#0c0c0c]');
                    }, 2000);
                } else {
                    icon.className = 'fa-solid fa-check text-emerald-500';
                    setTimeout(() => {
                        icon.className = originalIcon;
                    }, 2000);
                }
            });
        }

        // تابع یکپارچه برای باز و بسته کردن انواع Modal ها
        function toggleModal(modalId) {
            const modal = document.getElementById(modalId);
            const modalBody = modal.querySelector('.glass-card');
            
            if (modal.classList.contains('hidden')) {
                modal.classList.remove('hidden');
                modal.style.display = 'flex';
                setTimeout(() => {
                    modal.classList.remove('opacity-0');
                    if(modalBody) {
                        modalBody.classList.remove('scale-95');
                        modalBody.classList.add('scale-100');
                    }
                }, 10);
            } else {
                modal.classList.add('opacity-0');
                if(modalBody) {
                    modalBody.classList.remove('scale-100');
                    modalBody.classList.add('scale-95');
                }
                setTimeout(() => {
                    modal.classList.add('hidden');
                    modal.style.display = '';
                }, 300);
            }
        }
    </script>
</body>
</html>

ZQ_user_html

cat > "${PANEL_DIR}/templates/restarting.html" <<'ZQ_restarting_html'
{% extends 'base.html' %}
{% block title %}{{ t.panel_restarting }}{% endblock %}
{% block body %}
<meta http-equiv="refresh" content="6;url=/">
<div class="login-wrap">
  <div class="card" style="max-width:385px;text-align:center">
    <div class="restart-logo"><svg class="logo-svg" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="L2TP"><defs><linearGradient id="lgr" x1="10" y1="6" x2="54" y2="58" gradientUnits="userSpaceOnUse"><stop class="lg-a" offset="0"/><stop class="lg-b" offset="1"/></linearGradient></defs><path d="M32 4 L55.5 12.5 V28 C55.5 42.5 46 52.5 32 59.5 C18 52.5 8.5 42.5 8.5 28 V12.5 Z" stroke="url(#lgr)" stroke-width="3.4" stroke-linejoin="round" fill="url(#lgr)" fill-opacity="0.08"/><path d="M22 46.5 V29 C22 21.8 26.4 16 32 16 C37.6 16 42 21.8 42 29 V46.5" stroke="url(#lgr)" stroke-width="2.6" stroke-linecap="round"/><path d="M28 46.5 V31.5 C28 27 29.7 23.5 32 23.5 C34.3 23.5 36 27 36 31.5 V46.5" stroke="url(#lgr)" stroke-width="2" stroke-linecap="round" opacity="0.6"/><circle cx="32" cy="36.5" r="3" fill="url(#lgr)"/></svg></div>
    <h1 style="color:var(--tx)">{{ t.panel_restarting }}</h1>
    <p class="muted" style="margin-top:8px">{{ t.restarting_msg }}</p>
  </div>
</div>
{% endblock %}












ZQ_restarting_html

cat > "${PANEL_DIR}/templates/updating.html" <<'ZQ_updating_html'
{% extends 'base.html' %}
{% block title %}{{ t.updating_title }}{% endblock %}
{% block body %}
<meta http-equiv="refresh" content="15;url=/">
<style>
.upd-logo{width:66px;height:66px;border-radius:19px;display:grid;place-items:center;margin:0 auto 14px;
  background:var(--card3);border:1px solid var(--bd2);box-shadow:0 0 22px rgba(0,229,255,.22);
  animation:updspin 2.2s ease-in-out infinite}
@keyframes updspin{0%,100%{transform:rotate(0)}50%{transform:rotate(180deg)}}
.upd-bar{height:6px;background:rgba(255,255,255,.07);border-radius:99px;overflow:hidden;margin:18px 0 14px}
[data-theme=light] .upd-bar{background:#e2e8f4}
.upd-fill{height:100%;width:40%;border-radius:99px;
  background:linear-gradient(90deg,var(--neon-cyan),var(--neon-purple));
  box-shadow:0 0 12px rgba(0,229,255,.5);animation:updmv 1.6s ease-in-out infinite}
@keyframes updmv{0%{margin-left:-40%}100%{margin-left:100%}}
</style>
<div class="login-wrap">
  <div class="card" style="max-width:400px;text-align:center">
    <div class="upd-logo">
      <svg class="logo-svg" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
        <defs><linearGradient id="lgup" x1="10" y1="6" x2="54" y2="58" gradientUnits="userSpaceOnUse">
          <stop class="lg-a" offset="0"/><stop class="lg-b" offset="1"/></linearGradient></defs>
        <path d="M32 4 L55.5 12.5 V28 C55.5 42.5 46 52.5 32 59.5 C18 52.5 8.5 42.5 8.5 28 V12.5 Z" stroke="url(#lgup)" stroke-width="3.4" stroke-linejoin="round" fill="url(#lgup)" fill-opacity="0.08"/>
        <path d="M22 46.5 V29 C22 21.8 26.4 16 32 16 C37.6 16 42 21.8 42 29 V46.5" stroke="url(#lgup)" stroke-width="2.6" stroke-linecap="round"/>
        <circle cx="32" cy="36.5" r="3" fill="url(#lgup)"/>
      </svg>
    </div>
    <h1 style="color:var(--tx)">{{ t.updating_title }}</h1>
    <p class="muted" style="margin-top:8px;line-height:1.8">{{ t.updating_msg }}</p>
    <div class="upd-bar"><div class="upd-fill"></div></div>
    <span class="muted">v{{ panel_version }}</span>
  </div>
</div>
{% endblock %}









ZQ_updating_html

cat > "/root/ocserv-full-sync.sh" <<'ZQ_ENFORCE'
#!/bin/bash
set -euo pipefail
[ "$EUID" -eq 0 ] || { echo "Run with sudo."; exit 1; }

echo "[1/2] Kill expired/quota users..."
KILLED=0
KILLED=$(python3 << 'PYEOF'
import sqlite3
import subprocess
from datetime import datetime

db = sqlite3.connect("/opt/l2tp-panel/users.db")
db.row_factory = sqlite3.Row
users = db.execute("SELECT username, expires_at, traffic_limit_mb, used_bytes FROM users").fetchall()
db.close()

now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
count = 0

for u in users:
    expired = (u["expires_at"] <= now)
    used_mb = (u["used_bytes"] or 0) / (1024.0 * 1024.0)
    limit = u["traffic_limit_mb"] or 0
    quota = (limit > 0 and used_mb >= limit)
    if expired or quota:
        reason = "expired" if expired else "quota"
        subprocess.run(["pkill", "-f", "worker.*" + u["username"]], capture_output=True)
        print("  KILLED (%s): %s" % (reason, u["username"]))
        count += 1
print("COUNT:%d" % count)
PYEOF
)

echo "[2/2] Rebuild ocpasswd (blocked users removed)..."
python3 << 'PYEOF'
import sqlite3
import subprocess
from datetime import datetime

db = sqlite3.connect("/opt/l2tp-panel/users.db")
db.row_factory = sqlite3.Row
users = db.execute("SELECT username, password, expires_at, traffic_limit_mb, used_bytes FROM users").fetchall()
db.close()

now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

open("/etc/ocserv/ocpasswd", "w").close()
for u in users:
    expired = (u["expires_at"] <= now)
    used_mb = (u["used_bytes"] or 0) / (1024.0 * 1024.0)
    limit = u["traffic_limit_mb"] or 0
    quota = (limit > 0 and used_mb >= limit)
    if not expired and not quota:
        subprocess.run(
            ["ocpasswd", "-c", "/etc/ocserv/ocpasswd", "-g", "default", u["username"]],
            input=(u["password"] + "\n" + u["password"]).encode(),
            capture_output=True
        )
    else:
        print("  blocked: " + u["username"])
PYEOF

# If anyone was killed -> restart ocserv to drop their active sessions
if echo "$KILLED" | grep -q "COUNT:1\|COUNT:2\|COUNT:3\|COUNT:4\|COUNT:5"; then
  echo "  restarting ocserv (dropping blocked sessions)..."
  systemctl restart ocserv
  sleep 2
fi

echo "[OK] enforcement done"




ZQ_ENFORCE
chmod 755 "/root/ocserv-full-sync.sh"

# ---------- crons ----------
info "Setting up cron jobs..."
echo "* * * * * root python3 /opt/l2tp-panel/ocserv_online.py" > /etc/cron.d/ocserv-online
echo "* * * * * root python3 /opt/l2tp-panel/ocserv_traffic.py" > /etc/cron.d/ocserv-traffic
echo "* * * * * root bash /root/ocserv-full-sync.sh" > /etc/cron.d/ocserv-sync
chmod 644 /etc/cron.d/ocserv-*
systemctl restart cron 2>/dev/null || true

# ---------- services ----------
info "Creating services..."

cat > /etc/systemd/system/l2tp-panel.service <<PANELSVC
[Unit]
Description=3OUTHBOY PANEL Web UI
After=network.target

[Service]
WorkingDirectory=/opt/l2tp-panel
ExecStart=/usr/bin/gunicorn --workers 1 --threads 4 --bind 0.0.0.0:__PORT__ --timeout 60 panel:app
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
PANELSVC
sed -i "s/__PORT__/${PANEL_PORT}/" /etc/systemd/system/l2tp-panel.service

cat > /etc/systemd/system/l2tp-sync.service <<'SYNCSVC'
[Unit]
Description=3OUTHBOY PANEL - user sync

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /opt/l2tp-panel/sync_users.py
SYNCSVC

cat > /etc/systemd/system/l2tp-sync.timer <<'SYNCTMR'
[Unit]
Description=Run L2TP sync every 30 seconds

[Timer]
OnBootSec=30
OnUnitActiveSec=30
AccuracySec=5
Unit=l2tp-sync.service

[Install]
WantedBy=timers.target
SYNCTMR

# ---------- firewall ----------
if [ "${ENABLE_UFW,,}" != "n" ]; then
  info "Configuring UFW..."
  SSH_PORT="22"
  if [ -n "${SSH_CONNECTION:-}" ]; then
    SP="$(awk '{print $4}' <<<"$SSH_CONNECTION")"
    [[ "$SP" =~ ^[0-9]+$ ]] && SSH_PORT="$SP"
  fi
  ufw allow "${SSH_PORT}/tcp" >/dev/null
  ufw allow 500/udp >/dev/null
  ufw allow 4500/udp >/dev/null
  ufw allow 1701/udp >/dev/null
  ufw allow "${OCSERV_PORT}/tcp" >/dev/null
  ufw allow "${OCSERV_PORT}/udp" >/dev/null
  if [ -n "$ADMIN_IP" ]; then
    ufw allow from "$ADMIN_IP" to any port "$PANEL_PORT" proto tcp >/dev/null
  else
    ufw allow "${PANEL_PORT}/tcp" >/dev/null
  fi
  ufw route allow from 192.168.43.0/24 >/dev/null
  ufw route allow from 192.168.44.0/24 >/dev/null
  ufw route allow from 192.168.45.0/24 >/dev/null
  ufw --force enable >/dev/null
  ok "Firewall enabled"
fi

# ---------- start ----------
info "Starting services..."
systemctl daemon-reload
systemctl enable --now strongswan-starter >/dev/null 2>&1 || true
systemctl restart strongswan-starter
systemctl enable --now xl2tpd >/dev/null 2>&1 || true
systemctl restart xl2tpd
systemctl enable --now l2tp-nat >/dev/null 2>&1 || true
systemctl restart l2tp-nat
systemctl enable --now ocserv >/dev/null 2>&1 || true
systemctl restart ocserv
systemctl enable l2tp-panel >/dev/null 2>&1 || true
systemctl restart l2tp-panel
systemctl enable --now l2tp-sync.timer >/dev/null 2>&1 || true
python3 "${PANEL_DIR}/sync_users.py" 2>/dev/null || true
systemctl restart cron 2>/dev/null || true
ok "All services started."

echo
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}  3OUTHBOY PANEL — Multi-Protocol — Installed!      ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo -e " Panel URL       : ${CYAN}http://${PUB_IP}:${PANEL_PORT}${NC}"
echo -e " Admin username  : ${CYAN}${ADMIN_USER}${NC}"
echo -e " Admin password  : ${CYAN}${ADMIN_PASS}${NC}"
echo -e " IPSec PSK       : ${CYAN}${PSK}${NC}"
echo -e " L2TP/IPSec      : ${PUB_IP} (PSK)"
echo -e " IKEv2           : ${PUB_IP} (user/pass)"
echo -e " OpenConnect     : ${PUB_IP}:${OCSERV_PORT} (user/pass)"
echo -e " User status     : http://${PUB_IP}:${PANEL_PORT}/u/<USER_KEY>"
echo
warn "Save these credentials!"
warn "Open UDP 500/4500/1701, TCP+UDP ${OCSERV_PORT} + TCP ${PANEL_PORT} in provider firewall."
