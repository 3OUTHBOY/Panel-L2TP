#!/bin/bash
# =====================================================================
#   3OUTHBOY PANEL â€” L2TP/IPSec VPN + Web Management Panel  v1.0.0
#   Generated from live server state (build-installer.py)
#   Ubuntu 20.04 / 22.04 / 24.04
#   Interactive:  sudo bash install.sh
#   Unattended:   sudo bash install.sh --user admin --pass X --port 8080 --psk Y
# =====================================================================
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info(){ echo -e "${CYAN}[*]${NC} $1"; }
ok(){   echo -e "${GREEN}[OK]${NC} $1"; }
warn(){ echo -e "${YELLOW}[!]${NC} $1"; }
die(){  echo -e "${RED}[X]${NC} $1"; exit 1; }

[ "$EUID" -eq 0 ] || die "This script must be run with sudo."

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
while [ $# -gt 0 ]; do
  case "$1" in
    --user)     ADMIN_USER="$2"; shift 2 ;;
    --pass)     ADMIN_PASS="$2"; shift 2 ;;
    --port)     PANEL_PORT="$2"; shift 2 ;;
    --psk)      PSK="$2"; shift 2 ;;
    --admin-ip) ADMIN_IP="$2"; shift 2 ;;
    --tz)       SET_TZ="$2"; shift 2 ;;
    --no-ufw)   ENABLE_UFW="n"; shift ;;
    *) shift ;;
  esac
done

if [ -t 0 ]; then
  echo -e "${CYAN}============ 3OUTHBOY PANEL Installer ============${NC}"
  read -rp "Admin username [${ADMIN_USER}]: " v; ADMIN_USER="${v:-$ADMIN_USER}"
  read -rp "Admin password [${ADMIN_PASS}]: " v; ADMIN_PASS="${v:-$ADMIN_PASS}"
  read -rp "Panel port [${PANEL_PORT}]: " v; PANEL_PORT="${v:-$PANEL_PORT}"
  read -rp "IPSec PSK [${PSK}]: " v; PSK="${v:-$PSK}"
  read -rp "Admin IP for panel (empty = no restriction): " v; ADMIN_IP="${v:-$ADMIN_IP}"
  read -rp "Set timezone Asia/Tehran? [Y/n]: " v; SET_TZ="${v:-y}"
  read -rp "Enable UFW firewall? [Y/n]: " v; ENABLE_UFW="${v:-y}"
fi

ADMIN_USER="$(sanitize "$ADMIN_USER" | tr -cd 'A-Za-z0-9_.-')"
ADMIN_PASS="$(sanitize "$ADMIN_PASS")"; PSK="$(sanitize "$PSK")"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-$(rand_str 12)}"
PSK="${PSK:-$(rand_str 20)}"
[[ "$PANEL_PORT" =~ ^[1-9][0-9]{1,4}$ ]] || PANEL_PORT="8080"
if [ -n "$ADMIN_IP" ] && ! [[ "$ADMIN_IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]{1,2})?$ ]]; then
  warn "Invalid admin IP; panel will not be restricted."
  ADMIN_IP=""
fi

info "Installing packages (this may take a few minutes)..."
export DEBIAN_FRONTEND=noninteractive
systemctl disable --now strongswan-starter strongswan-swanctl >/dev/null 2>&1 || true
apt-get remove -y strongswan-starter strongswan-swanctl libreswan >/dev/null 2>&1 || true
apt-get update -y -qq
apt-get install -y -qq xl2tpd strongswan strongswan-starter \
  libcharon-extra-plugins libstrongswan-extra-plugins \
  ppp python3 python3-flask gunicorn ufw iptables curl >/dev/null
ok "Packages installed."

[ "${SET_TZ,,}" != "n" ] && timedatectl set-timezone Asia/Tehran >/dev/null 2>&1 && ok "Timezone: Asia/Tehran" || true

DEF_IF="$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}')"
[ -n "$DEF_IF" ] || die "Could not find the default network interface."

info "Detecting public IPv4 address..."
PUB_IP="$(curl -4 -s --max-time 6 https://api.ipify.org || true)"
[ -n "$PUB_IP" ] || PUB_IP="$(curl -4 -s --max-time 6 http://ipv4.icanhazip.com || true)"
[ -n "$PUB_IP" ] || PUB_IP="$(curl -4 -s --max-time 6 http://checkip.amazonaws.com || true)"
[[ "$PUB_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || die "Could not detect public IPv4 address."
ok "Public IPv4: ${PUB_IP}"

grep -q '^precedence ::ffff:0:0/96  100' /etc/gai.conf 2>/dev/null || \
  echo 'precedence ::ffff:0:0/96  100' >> /etc/gai.conf

TS="$(date +%Y%m%d%H%M%S)"
for f in /etc/ipsec.conf /etc/ipsec.secrets /etc/xl2tpd/xl2tpd.conf \
         /etc/ppp/options.xl2tpd /etc/ppp/chap-secrets; do
  [ -f "$f" ] && cp -a "$f" "${f}.bak-${TS}"
done

info "Configuring IPSec..."
printf '%%any %%any : PSK "%s"\n' "$PSK" > /etc/ipsec.secrets
chmod 600 /etc/ipsec.secrets
touch /etc/ipsec.d/passwd && chmod 600 /etc/ipsec.d/passwd

info "Enabling IP forwarding..."
sed -i '/^#\?net.ipv4.ip_forward/d' /etc/sysctl.conf
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -w net.ipv4.ip_forward=1 >/dev/null

info "Writing VPN configuration..."

cat > /etc/ipsec.conf <<IPSECEOF
# L2TP/IPSec PSK + XAuth PSK - 3OUTHBOY L2TP Panel (strongSwan)
config setup
    uniqueids=no

conn shared
    keyexchange=ikev1
    left=%defaultroute
     leftid=${PUB_IP}
    right=%any
    forceencaps=yes
    authby=psk
    pfs=no
    rekey=no
    dpddelay=30
    dpdaction=clear
    ikelifetime=24h
    lifetime=24h
    ike=aes256-sha2_256-modp2048,aes128-sha2_256-modp2048,aes256-sha1-modp2048,aes128-sha1-modp2048,aes256-sha2_256-curve25519,aes128-sha2_256-curve25519,aes256-sha1-curve25519,aes128-sha1-curve25519,aes256-sha2_256-ecp256,aes128-sha2_256-ecp256,aes256-sha2_256-modp1024,aes128-sha2_256-modp1024,aes256-sha1-modp1024,aes128-sha1-modp1024
    esp=aes256-sha2_256,aes128-sha2_256,aes256-sha2_512,aes256-sha1,aes128-sha1,aes128gcm16,aes256gcm16

conn l2tp-psk
    also=shared
    auto=add
    leftprotoport=17/1701
    rightprotoport=17/%any
    type=transport

conn xauth-psk
    also=shared
    auto=add
    leftsubnet=0.0.0.0/0
    rightaddresspool=192.168.44.10-192.168.44.250
    modecfgdns="8.8.8.8 8.8.4.4"
    xauth=server
    modeconfig=push
    cisco_unity=yes


IPSECEOF

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
        fi
    fi
    rm -f "$SDIR/$PEERNAME" "$PDIR/$PEERNAME" 2>/dev/null
fi
/usr/bin/python3 /opt/l2tp-panel/iface_down.py "$1" >/dev/null 2>&1
rm -f "$IDIR/$1" 2>/dev/null
exit 0


IPDOWNEOF
chmod 755 /etc/ppp/ip-down.d/90l2tp-panel

cat > /usr/local/sbin/l2tp-nat.sh <<'NATEOF'
#!/bin/sh
IF="ens3"
add(){ /sbin/iptables -t nat -C POSTROUTING -s "$1" -o "$IF" -j MASQUERADE 2>/dev/null || /sbin/iptables -t nat -A POSTROUTING -s "$1" -o "$IF" -j MASQUERADE; }
del(){ /sbin/iptables -t nat -D POSTROUTING -s "$1" -o "$IF" -j MASQUERADE 2>/dev/null || true; }
chain(){
  /sbin/iptables -t nat -N L2TP_DNS 2>/dev/null || true
  /sbin/iptables -t nat -C PREROUTING -j L2TP_DNS 2>/dev/null || /sbin/iptables -t nat -A PREROUTING -j L2TP_DNS
}
mss(){ /sbin/iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || /sbin/iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu; }
case "$1" in
  start) add 192.168.43.0/24; add 192.168.44.0/24; chain; mss ;;
  stop)  del 192.168.43.0/24; del 192.168.44.0/24; /sbin/iptables -t nat -F L2TP_DNS 2>/dev/null || true ;;
esac


NATEOF
chmod 755 /usr/local/sbin/l2tp-nat.sh

sed -i "s|^IF=.*|IF=\"${DEF_IF}\"|" /usr/local/sbin/l2tp-nat.sh

mkdir -p /run/l2tp-sessions /run/l2tp-ifaces /run/l2tp-peerip /etc/ppp/dns-map
chmod 700 /run/l2tp-sessions /run/l2tp-ifaces /run/l2tp-peerip /etc/ppp/dns-map

cat > /etc/systemd/system/l2tp-nat.service <<'NATSVC'
[Unit]
Description=3OUTHBOY PANEL - NAT for VPN clients
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/l2tp-nat.sh start
ExecStop=/usr/local/sbin/l2tp-nat.sh stop

[Install]
WantedBy=multi-user.target
NATSVC

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

info "Writing panel files..."

cat > ${PANEL_DIR}/panel.py <<'PANELPY'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""3OUTHBOY PANEL (fa/en) â€” expiry, quotas, DNS, keys, restart, self-update."""
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
PANEL_VERSION = '2.0.0'
UPDATE_URL = 'https://raw.githubusercontent.com/3OUTHBOY/Panel-L2TP/main/install.sh'
UPDATE_LOG = '/var/log/l2tp-panel-update.log'

with open(os.path.join(BASE, 'config.json'), encoding='utf-8') as fh:
    CFG = json.load(fh)

TRANSLATIONS = {
 'fa': {
  'brand':'Ù¾Ù†Ù„ 3OUTHBOY','header_title':'Ù¾Ù†Ù„ 3OUTHBOY','login_title':'Ù¾Ù†Ù„ 3OUTHBOY',
  'username':'Ù†Ø§Ù… Ú©Ø§Ø±Ø¨Ø±ÛŒ','password':'Ø±Ù…Ø² Ø¹Ø¨ÙˆØ±','login_btn':'ÙˆØ±ÙˆØ¯',
  'err_credentials':'Ù†Ø§Ù… Ú©Ø§Ø±Ø¨Ø±ÛŒ ÛŒØ§ Ø±Ù…Ø² Ø¹Ø¨ÙˆØ± Ø§Ø´ØªØ¨Ø§Ù‡ Ø§Ø³Øª.',
  'err_locked':'ØªÙ„Ø§Ø´â€ŒÙ‡Ø§ÛŒ Ù†Ø§Ù…ÙˆÙÙ‚ Ø²ÛŒØ§Ø¯ Ø¨ÙˆØ¯Ù‡Ø› Ûµ Ø¯Ù‚ÛŒÙ‚Ù‡ Ø¨Ø¹Ø¯ Ø¯ÙˆØ¨Ø§Ø±Ù‡ Ø§Ù…ØªØ­Ø§Ù† Ú©Ù†ÛŒØ¯.',
  'server_address':'Ø¢Ø¯Ø±Ø³ Ø³Ø±ÙˆØ±','psk_label':'Ú©Ù„ÛŒØ¯ Ù…Ø´ØªØ±Ú© (PSK)','active_users':'Ú©Ø§Ø±Ø¨Ø±Ø§Ù† ÙØ¹Ø§Ù„',
  'online_sessions':'Ù†Ø´Ø³Øªâ€ŒÙ‡Ø§ÛŒ Ù…ØªØµÙ„','services_status':'ÙˆØ¶Ø¹ÛŒØª Ø³Ø±ÙˆÛŒØ³â€ŒÙ‡Ø§','of_word':'Ø§Ø²',
  'add_user_title':'Ø§ÙØ²ÙˆØ¯Ù† Ú©Ø§Ø±Ø¨Ø± Ø¬Ø¯ÛŒØ¯','password_auto':'Ø±Ù…Ø² Ø¹Ø¨ÙˆØ± (Ø®Ø§Ù„ÛŒ = Ø®ÙˆØ¯Ú©Ø§Ø±)',
  'auto_placeholder':'Ø®ÙˆØ¯Ú©Ø§Ø±','days_label':'Ù…Ø¯Øª Ø§Ø¹ØªØ¨Ø§Ø± (Ø±ÙˆØ²)',
  'exact_expiry':'ØªØ§Ø±ÛŒØ® Ùˆ Ø³Ø§Ø¹Øª Ø¯Ù‚ÛŒÙ‚ Ø§Ù†Ù‚Ø¶Ø§ (Ø§Ø®ØªÛŒØ§Ø±ÛŒ)','add_btn':'Ø§ÙØ²ÙˆØ¯Ù† Ú©Ø§Ø±Ø¨Ø±',
  'exact_note':'Ø§Ú¯Ø± ØªØ§Ø±ÛŒØ® Ø¯Ù‚ÛŒÙ‚ Ø±Ø§ Ø§Ù†ØªØ®Ø§Ø¨ Ú©Ù†ÛŒØ¯ ÙÛŒÙ„Ø¯ Â«Ø±ÙˆØ²Â» Ù†Ø§Ø¯ÛŒØ¯Ù‡ Ú¯Ø±ÙØªÙ‡ Ù…ÛŒâ€ŒØ´ÙˆØ¯.',
  'traffic_label':'Ù…Ø­Ø¯ÙˆØ¯ÛŒØª Ø­Ø¬Ù… (GB)','traffic_ph':'Ù†Ø§Ù…Ø­Ø¯ÙˆØ¯',
  'dns1_label':'DNS Ø§ÙˆÙ„ (Ø®Ø§Ù„ÛŒ = Ù¾ÛŒØ´â€ŒÙØ±Ø¶)','dns2_label':'DNS Ø¯ÙˆÙ… (Ø®Ø§Ù„ÛŒ = Ù¾ÛŒØ´â€ŒÙØ±Ø¶)',
  'users_title':'Ú©Ø§Ø±Ø¨Ø±Ø§Ù†','th_username':'Ù†Ø§Ù… Ú©Ø§Ø±Ø¨Ø±ÛŒ','th_password':'Ø±Ù…Ø² Ø¹Ø¨ÙˆØ±','th_expiry':'Ø§Ù†Ù‚Ø¶Ø§',
  'th_remaining':'Ø¨Ø§Ù‚ÛŒâ€ŒÙ…Ø§Ù†Ø¯Ù‡','th_traffic':'Ø­Ø¬Ù… Ù…ØµØ±ÙÛŒ','th_dns':'DNS Ø§Ø®ØªØµØ§ØµÛŒ','th_key':'Ú©Ø¯ Ú©Ø§Ø±Ø¨Ø±',
  'default_dns':'Ù¾ÛŒØ´â€ŒÙØ±Ø¶','th_status':'ÙˆØ¶Ø¹ÛŒØª','th_actions':'Ø¹Ù…Ù„ÛŒØ§Øª','badge_active':'ÙØ¹Ø§Ù„',
  'badge_soon':'Ø¯Ø± Ø­Ø§Ù„ Ø§ØªÙ…Ø§Ù…','badge_expired':'Ù…Ù†Ù‚Ø¶ÛŒ','badge_quota':'Ø­Ø¬Ù… ØªÙ…Ø§Ù… Ø´Ø¯',
  'renew_btn':'ØªÙ…Ø¯ÛŒØ¯','online_tip':'Ø¢Ù†Ù„Ø§ÛŒÙ†','no_users':'Ù‡Ù†ÙˆØ² Ú©Ø§Ø±Ø¨Ø±ÛŒ Ø§Ø¶Ø§ÙÙ‡ Ù†Ø´Ø¯Ù‡ Ø§Ø³Øª.',
  'delete_confirm':'Ø§ÛŒÙ† Ú©Ø§Ø±Ø¨Ø± Ø­Ø°Ù Ø´ÙˆØ¯ØŸ','edit_title':'ÙˆÛŒØ±Ø§ÛŒØ´ Ú©Ø§Ø±Ø¨Ø±',
  'new_password':'Ø±Ù…Ø² Ø¹Ø¨ÙˆØ± Ø¬Ø¯ÛŒØ¯ (Ø®Ø§Ù„ÛŒ = Ø¨Ø¯ÙˆÙ† ØªØºÛŒÛŒØ±)',
  'new_expiry':'ØªØ§Ø±ÛŒØ® Ùˆ Ø³Ø§Ø¹Øª Ø§Ù†Ù‚Ø¶Ø§ÛŒ Ø¬Ø¯ÛŒØ¯ (Ø®Ø§Ù„ÛŒ = Ø¨Ø¯ÙˆÙ† ØªØºÛŒÛŒØ±)',
  'new_traffic':'Ù…Ø­Ø¯ÙˆØ¯ÛŒØª Ø­Ø¬Ù… Ø¬Ø¯ÛŒØ¯ Ø¨Ù‡ GB (Ø®Ø§Ù„ÛŒ = Ø¨Ø¯ÙˆÙ† ØªØºÛŒÛŒØ±ØŒ Û° = Ù†Ø§Ù…Ø­Ø¯ÙˆØ¯)',
  'new_dns1':'DNS Ø§ÙˆÙ„ (Ø®Ø§Ù„ÛŒ = Ø­Ø°Ù DNS Ø§Ø®ØªØµØ§ØµÛŒ)','new_dns2':'DNS Ø¯ÙˆÙ… (Ø®Ø§Ù„ÛŒ = Ø­Ø°Ù DNS Ø§Ø®ØªØµØ§ØµÛŒ)',
  'new_key':'Ú©Ø¯ Ú©Ø§Ø±Ø¨Ø± (Ø®Ø§Ù„ÛŒ = Ø¨Ø¯ÙˆÙ† ØªØºÛŒÛŒØ±)','cancel':'Ø§Ù†ØµØ±Ø§Ù','save':'Ø°Ø®ÛŒØ±Ù‡',
  'sync_btn':'ðŸ”„ Ù‡Ù…Ú¯Ø§Ù…â€ŒØ³Ø§Ø²ÛŒ','restart_vpn_btn':'ðŸš€ Ø±ÛŒØ³ØªØ§Ø±Øª VPN','restart_panel_btn':'â™»ï¸ Ø±ÛŒØ³ØªØ§Ø±Øª Ù¾Ù†Ù„',
  'restart_vpn_confirm':'Ø³Ø±ÙˆÛŒØ³â€ŒÙ‡Ø§ÛŒ VPN Ø±ÛŒØ³ØªØ§Ø±Øª Ø´ÙˆÙ†Ø¯ØŸ Ú©Ø§Ø±Ø¨Ø±Ø§Ù† Ù…ØªØµÙ„ Ù…ÙˆÙ‚ØªØ§Ù‹ Ù‚Ø·Ø¹ Ù…ÛŒâ€ŒØ´ÙˆÙ†Ø¯.',
  'restart_panel_confirm':'Ù¾Ù†Ù„ Ø±ÛŒØ³ØªØ§Ø±Øª Ø´ÙˆØ¯ØŸ Ú†Ù†Ø¯ Ø«Ø§Ù†ÛŒÙ‡ Ø·ÙˆÙ„ Ù…ÛŒâ€ŒÚ©Ø´Ø¯.',
  'vpn_restarted':'Ù‡Ù…Ù‡ Ø³Ø±ÙˆÛŒØ³â€ŒÙ‡Ø§ÛŒ VPN Ø¨Ø§ Ù…ÙˆÙÙ‚ÛŒØª Ø±ÛŒØ³ØªØ§Ø±Øª Ø´Ø¯Ù†Ø¯.',
  'vpn_restart_failed':'Ø¨Ø¹Ø¶ÛŒ Ø³Ø±ÙˆÛŒØ³â€ŒÙ‡Ø§ Ø±ÛŒØ³ØªØ§Ø±Øª Ù†Ø´Ø¯Ù†Ø¯! Ø¨Ø§ journalctl Ø¨Ø±Ø±Ø³ÛŒ Ú©Ù†ÛŒØ¯.',
  'panel_restarting':'Ù¾Ù†Ù„ Ø¯Ø± Ø­Ø§Ù„ Ø±ÛŒØ³ØªØ§Ø±Øª Ø§Ø³Øª...',
  'restarting_msg':'Ú†Ù†Ø¯ Ø«Ø§Ù†ÛŒÙ‡ ØµØ¨Ø± Ú©Ù†ÛŒØ¯Ø› ØµÙØ­Ù‡ Ø¨Ù‡ ØµÙˆØ±Øª Ø®ÙˆØ¯Ú©Ø§Ø± Ø¨Ø§Ø±Ú¯Ø°Ø§Ø±ÛŒ Ù…ÛŒâ€ŒØ´ÙˆØ¯.',
  'update_btn':'ðŸ”„ Ø¢Ù¾Ø¯ÛŒØª Ù¾Ù†Ù„','updating_title':'Ø¯Ø± Ø­Ø§Ù„ Ø¢Ù¾Ø¯ÛŒØª Ù¾Ù†Ù„...',
  'updating_msg':'Ù†Ø³Ø®Ù‡ Ø¬Ø¯ÛŒØ¯ Ø§Ø² Ú¯ÛŒØªâ€ŒÙ‡Ø§Ø¨ Ø¯Ø± Ø­Ø§Ù„ Ø¯Ø§Ù†Ù„ÙˆØ¯ Ùˆ Ù†ØµØ¨ Ø§Ø³Øª. Ú†Ù†Ø¯ Ø¯Ù‚ÛŒÙ‚Ù‡ ØµØ¨Ø± Ú©Ù†ÛŒØ¯Ø› ØµÙØ­Ù‡ Ø®ÙˆØ¯Ú©Ø§Ø± Ø¨Ø§Ø²Ù…ÛŒâ€ŒÚ¯Ø±Ø¯Ø¯ Ùˆ Ø¨Ø§ÛŒØ¯ Ø¯ÙˆØ¨Ø§Ø±Ù‡ ÙˆØ§Ø±Ø¯ Ø´ÙˆÛŒØ¯.',
  'update_confirm':'Ù¾Ù†Ù„ Ø§Ø² Ú¯ÛŒØªâ€ŒÙ‡Ø§Ø¨ Ø¢Ù¾Ø¯ÛŒØª Ø´ÙˆØ¯ØŸ Ú†Ù†Ø¯ Ø¯Ù‚ÛŒÙ‚Ù‡ Ø·ÙˆÙ„ Ù…ÛŒâ€ŒÚ©Ø´Ø¯ Ùˆ Ø¨Ø¹Ø¯Ø´ Ø¨Ø§ÛŒØ¯ Ø¯ÙˆØ¨Ø§Ø±Ù‡ Ù„Ø§Ú¯ÛŒÙ† Ú©Ù†ÛŒØ¯.',
  'update_failed':'Ø¢Ù¾Ø¯ÛŒØª Ù†Ø§Ù…ÙˆÙÙ‚ Ø¨ÙˆØ¯! Ø§ØªØµØ§Ù„ Ø³Ø±ÙˆØ± Ø¨Ù‡ Ú¯ÛŒØªâ€ŒÙ‡Ø§Ø¨ Ø±Ø§ Ø¨Ø±Ø±Ø³ÛŒ Ú©Ù†ÛŒØ¯.',
  'logout_btn':'Ø®Ø±ÙˆØ¬','copy_tip':'Ú©Ù¾ÛŒ','show_tip':'Ù†Ù…Ø§ÛŒØ´',
  'reset_traffic_tip':'ØµÙØ± Ú©Ø±Ø¯Ù† Ø­Ø¬Ù… Ù…ØµØ±ÙÛŒ','regen_key_tip':'ØªÙˆÙ„ÛŒØ¯ Ú©Ø¯ Ø¬Ø¯ÛŒØ¯',
  'status_link_tip':'ØµÙØ­Ù‡ ÙˆØ¶Ø¹ÛŒØª Ú©Ø§Ø±Ø¨Ø±','theme_tip':'Ø­Ø§Ù„Øª Ø±ÙˆØ´Ù† / ØªØ§Ø±ÛŒÚ©',
  'invalid_username':'Ù†Ø§Ù… Ú©Ø§Ø±Ø¨Ø±ÛŒ Ù†Ø§Ù…Ø¹ØªØ¨Ø± Ø§Ø³Øª (Û³ ØªØ§ Û³Û² Ú©Ø§Ø±Ø§Ú©ØªØ± Ù„Ø§ØªÛŒÙ†/Ø¹Ø¯Ø¯).',
  'bad_pw_chars':'Ø±Ù…Ø² Ø¹Ø¨ÙˆØ± Ù†Ø¨Ø§ÛŒØ¯ Ø´Ø§Ù…Ù„ ÙØ§ØµÙ„Ù‡ ÛŒØ§ Ú©Ø§Ø±Ø§Ú©ØªØ±Ù‡Ø§ÛŒ " \' \\ * : ; # Ø¨Ø§Ø´Ø¯.',
  'bad_pw_chars_short':'Ø±Ù…Ø² Ø¹Ø¨ÙˆØ± Ø¯Ø§Ø±Ø§ÛŒ Ú©Ø§Ø±Ø§Ú©ØªØ±Ù‡Ø§ÛŒ ØºÛŒØ±Ù…Ø¬Ø§Ø² Ø§Ø³Øª.',
  'invalid_expiry':'Ù‚Ø§Ù„Ø¨ ØªØ§Ø±ÛŒØ®/Ø³Ø§Ø¹Øª Ø§Ù†Ù‚Ø¶Ø§ Ù†Ø§Ù…Ø¹ØªØ¨Ø± Ø§Ø³Øª.',
  'invalid_days':'ØªØ¹Ø¯Ø§Ø¯ Ø±ÙˆØ² Ø¨Ø§ÛŒØ¯ Ø¨ÛŒÙ† Û± ØªØ§ Û³Û¶ÛµÛ° Ø¨Ø§Ø´Ø¯.','invalid_days_short':'ØªØ¹Ø¯Ø§Ø¯ Ø±ÙˆØ² Ù†Ø§Ù…Ø¹ØªØ¨Ø± Ø§Ø³Øª.',
  'invalid_date':'Ù‚Ø§Ù„Ø¨ ØªØ§Ø±ÛŒØ® Ù†Ø§Ù…Ø¹ØªØ¨Ø± Ø§Ø³Øª.','invalid_traffic':'Ù…Ø­Ø¯ÙˆØ¯ÛŒØª Ø­Ø¬Ù… Ù†Ø§Ù…Ø¹ØªØ¨Ø± Ø§Ø³Øª.',
  'invalid_dns':'Ø¢Ø¯Ø±Ø³ DNS Ù†Ø§Ù…Ø¹ØªØ¨Ø± Ø§Ø³Øª (Ø¨Ø§ÛŒØ¯ IPv4 Ø¨Ø§Ø´Ø¯).',
  'invalid_key':'Ú©Ø¯ Ú©Ø§Ø±Ø¨Ø± Ù†Ø§Ù…Ø¹ØªØ¨Ø± Ø§Ø³Øª (Û¸ ØªØ§ Û³Û² Ú©Ø§Ø±Ø§Ú©ØªØ± Ù„Ø§ØªÛŒÙ†/Ø¹Ø¯Ø¯).',
  'user_exists':'Ù†Ø§Ù… Ú©Ø§Ø±Ø¨Ø±ÛŒ Â«{username}Â» Ù‚Ø¨Ù„Ø§Ù‹ Ø«Ø¨Øª Ø´Ø¯Ù‡ Ø§Ø³Øª.',
  'user_added':'Ú©Ø§Ø±Ø¨Ø± Â«{username}Â» Ø§Ø¶Ø§ÙÙ‡ Ø´Ø¯. Ø±Ù…Ø² Ø¹Ø¨ÙˆØ±: {password}',
  'user_not_found':'Ú©Ø§Ø±Ø¨Ø± Ù¾ÛŒØ¯Ø§ Ù†Ø´Ø¯.','renewed':'Ø§Ø¹ØªØ¨Ø§Ø± Ú©Ø§Ø±Ø¨Ø± ØªÙ…Ø¯ÛŒØ¯ Ø´Ø¯.',
  'nothing_changed':'Ú†ÛŒØ²ÛŒ Ø¨Ø±Ø§ÛŒ ØªØºÛŒÛŒØ± ÙˆØ§Ø±Ø¯ Ù†Ø´Ø¯Ù‡ Ø§Ø³Øª.','changes_saved':'ØªØºÛŒÛŒØ±Ø§Øª Ø°Ø®ÛŒØ±Ù‡ Ø´Ø¯.',
  'user_deleted':'Ú©Ø§Ø±Ø¨Ø± Ø­Ø°Ù Ø´Ø¯.','sync_done':'Ù‡Ù…Ú¯Ø§Ù…â€ŒØ³Ø§Ø²ÛŒ Ø§Ù†Ø¬Ø§Ù… Ø´Ø¯.',
  'traffic_reset':'Ø´Ù…Ø§Ø±Ù†Ø¯Ù‡ Ø­Ø¬Ù… Ú©Ø§Ø±Ø¨Ø± ØµÙØ± Ø´Ø¯.',
  'key_regenerated':'Ú©Ø¯ Ø¬Ø¯ÛŒØ¯ ØªÙˆÙ„ÛŒØ¯ Ø´Ø¯ (Ù„ÛŒÙ†Ú© Ù‚Ø¨Ù„ÛŒ Ø¯ÛŒÚ¯Ø± Ú©Ø§Ø± Ù†Ù…ÛŒâ€ŒÚ©Ù†Ø¯).',
  'invalid_request':'Ø¯Ø±Ø®ÙˆØ§Ø³Øª Ù†Ø§Ù…Ø¹ØªØ¨Ø± Ø±Ø¯ Ø´Ø¯.','status_title':'ÙˆØ¶Ø¹ÛŒØª Ø§Ø´ØªØ±Ø§Ú© VPN',
  'st_server':'Ø¢Ø¯Ø±Ø³ Ø³Ø±ÙˆØ±','st_type':'Ù†ÙˆØ¹ Ø§ØªØµØ§Ù„','st_psk':'Ú©Ù„ÛŒØ¯ Ù…Ø´ØªØ±Ú© (PSK)',
  'st_dns':'DNS','st_dns_default':'Ù¾ÛŒØ´â€ŒÙØ±Ø¶ Ø³Ø±ÙˆØ±','st_expiry':'ØªØ§Ø±ÛŒØ® Ø§Ù†Ù‚Ø¶Ø§',
  'st_remaining':'Ø²Ù…Ø§Ù† Ø¨Ø§Ù‚ÛŒâ€ŒÙ…Ø§Ù†Ø¯Ù‡','st_traffic':'Ø­Ø¬Ù… Ù…ØµØ±ÙÛŒ',
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
  'sync_btn':'ðŸ”„ Sync','restart_vpn_btn':'ðŸš€ Restart VPN','restart_panel_btn':'â™»ï¸ Restart Panel',
  'restart_vpn_confirm':'Restart VPN services? Connected users will be temporarily disconnected.',
  'restart_panel_confirm':'Restart the panel? Takes a few seconds.',
  'vpn_restarted':'All VPN services restarted successfully.',
  'vpn_restart_failed':'Some services failed to restart! Check journalctl.',
  'panel_restarting':'Panel is restarting...',
  'restarting_msg':'Please wait; this page will reload automatically.',
  'update_btn':'ðŸ”„ Update Panel','updating_title':'Updating panel...',
  'updating_msg':'Downloading and installing the new version from GitHub. This takes a few minutes; the page will return automatically and you will need to log in again.',
  'update_confirm':'Update the panel from GitHub? Takes a few minutes and you will need to log in again.',
  'update_failed':'Update failed! Check server connectivity to GitHub.',
  'logout_btn':'Logout','copy_tip':'Copy','show_tip':'Show',
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

def get_lang(): return session.get('lang', DEFAULT_LANG)

def T(key, **kwargs):
    text = TRANSLATIONS.get(get_lang(), TRANSLATIONS[DEFAULT_LANG]).get(key) \
        or TRANSLATIONS['en'].get(key, key)
    return text.format(**kwargs) if kwargs else text

def fmt_remaining(secs, lang):
    d, h, m = int(secs // 86400), int((secs % 86400) // 3600), int((secs % 3600) // 60)
    if lang == 'fa':
        if d > 0: return '{} Ø±ÙˆØ² Ùˆ {} Ø³Ø§Ø¹Øª'.format(d, h)
        if h > 0: return '{} Ø³Ø§Ø¹Øª Ùˆ {} Ø¯Ù‚ÛŒÙ‚Ù‡'.format(h, m)
        return '{} Ø¯Ù‚ÛŒÙ‚Ù‡'.format(max(m, 1))
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
            dns_key TEXT NOT NULL DEFAULT '')''')
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
               if limit_mb > 0 else '{} / âˆž'.format(fmt_traffic(used)))
    remaining = fmt_remaining(secs, lang) if not expired and not quota_exceeded else 'â€”'
    return {'id': row['id'], 'username': row['username'], 'password': row['password'],
            'expires': row['expires_at'],
            'expires_input': row['expires_at'][:16].replace(' ', 'T'),
            'remaining': remaining, 'expired': expired,
            'soon': (not expired) and secs < 3 * 86400,
            'traffic': traffic, 'quota_exceeded': quota_exceeded,
            'limit_gb': round(limit_mb / 1024.0, 2), 'traffic_pct': traffic_pct,
            'dns1': row['dns1'] or '', 'dns2': row['dns2'] or '',
            'key': row['dns_key'] or ''}

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
        flash(T('invalid_request'))
        return redirect(url_for('index') if session.get('admin') else url_for('login'))
    return None

@app.route('/lang/<string:code>')
def set_lang(code):
    if code in TRANSLATIONS:
        session['lang'] = code
    return redirect(request.referrer or url_for('index'))

@app.route('/login', methods=['GET', 'POST'])
def login():
    error = None
    if request.method == 'POST':
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
    return render_template('login.html', error=error)

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

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
    svc = {'ipsec': service_active('strongswan-starter') or service_active('ipsec'),
           'xl2tpd': service_active('xl2tpd'), 'nat': service_active('l2tp-nat')}
    return render_template('index.html', users=users, server_ip=SERVER_IP, psk=CFG['psk'],
                           active_count=active_count, total_count=len(users),
                           online_count=len(online_users), svc=svc)

@app.route('/u/<string:key>')
def user_status(key):
    if not KEY_RE.match(key): abort(404)
    conn = get_db()
    try:
        row = conn.execute('SELECT * FROM users WHERE dns_key = ?', (key,)).fetchone()
    finally:
        conn.close()
    if row is None: abort(404)
    return render_template('user.html', u=user_row_to_dict(row),
                           server_ip=SERVER_IP, psk=CFG['psk'])

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
        flash(T('invalid_username')); return redirect(url_for('index'))
    if BAD_PW_CHARS & set(password):
        flash(T('bad_pw_chars')); return redirect(url_for('index'))
    if not password: password = gen_password()
    for d in (dns1, dns2):
        if d and not IPV4_RE.match(d):
            flash(T('invalid_dns')); return redirect(url_for('index'))
    limit_mb = parse_traffic_gb(traffic_raw)
    if traffic_raw and limit_mb is None:
        flash(T('invalid_traffic')); return redirect(url_for('index'))
    now = datetime.now()
    if exact:
        expires_dt = parse_dt(exact)
        if expires_dt is None:
            flash(T('invalid_expiry')); return redirect(url_for('index'))
    else:
        try: days = int(days_raw)
        except ValueError: days = 0
        if days <= 0 or days > 3650:
            flash(T('invalid_days')); return redirect(url_for('index'))
        expires_dt = now + timedelta(days=days)
    try:
        db_execute('INSERT INTO users (username, password, expires_at, created_at, '
                   'traffic_limit_mb, dns1, dns2, dns_key) VALUES (?,?,?,?,?,?,?,?)',
                   (username, password, expires_dt.strftime(DT_FMT), now.strftime(DT_FMT),
                    limit_mb, dns1, dns2, gen_key(20)))
    except sqlite3.IntegrityError:
        flash(T('user_exists', username=username)); return redirect(url_for('index'))
    run_sync()
    flash(T('user_added', username=username, password=password))
    return redirect(url_for('index'))

@app.route('/renew/<int:user_id>', methods=['POST'])
@login_required
def renew_user(user_id):
    try: days = int(request.form.get('days', ''))
    except ValueError: days = 0
    if days <= 0 or days > 3650:
        flash(T('invalid_days_short')); return redirect(url_for('index'))
    conn = get_db()
    try:
        row = conn.execute('SELECT expires_at FROM users WHERE id = ?', (user_id,)).fetchone()
    finally:
        conn.close()
    if row is None:
        flash(T('user_not_found')); return redirect(url_for('index'))
    current = datetime.strptime(row['expires_at'], DT_FMT)
    base = current if current > datetime.now() else datetime.now()
    db_execute('UPDATE users SET expires_at = ? WHERE id = ?',
               ((base + timedelta(days=days)).strftime(DT_FMT), user_id))
    run_sync(); flash(T('renewed'))
    return redirect(url_for('index'))

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
        flash(T('nothing_changed')); return redirect(url_for('index'))
    conn = get_db()
    try:
        row = conn.execute('SELECT username FROM users WHERE id = ?', (user_id,)).fetchone()
    finally:
        conn.close()
    if row is None:
        flash(T('user_not_found')); return redirect(url_for('index'))
    changed_pw = False
    if exact:
        dt = parse_dt(exact)
        if dt is None:
            flash(T('invalid_date')); return redirect(url_for('index'))
        db_execute('UPDATE users SET expires_at = ? WHERE id = ?', (dt.strftime(DT_FMT), user_id))
    if password:
        if BAD_PW_CHARS & set(password):
            flash(T('bad_pw_chars_short')); return redirect(url_for('index'))
        db_execute('UPDATE users SET password = ? WHERE id = ?', (password, user_id))
        changed_pw = True
    if traffic_raw:
        limit_mb = parse_traffic_gb(traffic_raw)
        if limit_mb is None:
            flash(T('invalid_traffic')); return redirect(url_for('index'))
        db_execute('UPDATE users SET traffic_limit_mb = ? WHERE id = ?', (limit_mb, user_id))
    for d in (dns1, dns2):
        if d and not IPV4_RE.match(d):
            flash(T('invalid_dns')); return redirect(url_for('index'))
    db_execute('UPDATE users SET dns1 = ?, dns2 = ? WHERE id = ?', (dns1, dns2, user_id))
    if key_raw:
        if not KEY_RE.match(key_raw):
            flash(T('invalid_key')); return redirect(url_for('index'))
        db_execute('UPDATE users SET dns_key = ? WHERE id = ?', (key_raw, user_id))
    if changed_pw: kill_session(row['username'])
    run_sync(); flash(T('changes_saved'))
    return redirect(url_for('index'))

@app.route('/regen-key/<int:user_id>', methods=['POST'])
@login_required
def regen_key(user_id):
    db_execute('UPDATE users SET dns_key = ? WHERE id = ?', (gen_key(20), user_id))
    flash(T('key_regenerated'))
    return redirect(url_for('index'))

@app.route('/reset-traffic/<int:user_id>', methods=['POST'])
@login_required
def reset_traffic(user_id):
    db_execute('UPDATE users SET used_bytes = 0 WHERE id = ?', (user_id,))
    run_sync(); flash(T('traffic_reset'))
    return redirect(url_for('index'))

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
    run_sync(); flash(T('user_deleted'))
    return redirect(url_for('index'))

@app.route('/sync', methods=['POST'])
@login_required
def sync_now():
    run_sync(); flash(T('sync_done'))
    return redirect(url_for('index'))

@app.route('/restart-vpn', methods=['POST'])
@login_required
def restart_vpn():
    ok1 = restart_service('strongswan-starter') or restart_service('ipsec')
    ok2 = restart_service('xl2tpd')
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

init_db()

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)

PANELPY
chmod 755 ${PANEL_DIR}/panel.py

cat > ${PANEL_DIR}/sync_users.py <<'SYNCPY'
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
<link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg%20xmlns%3D%27http%3A//www.w3.org/2000/svg%27%20viewBox%3D%270%200%2064%2064%27%3E%3Cdefs%3E%3ClinearGradient%20id%3D%27g%27%20x1%3D%2710%27%20y1%3D%276%27%20x2%3D%2754%27%20y2%3D%2758%27%20gradientUnits%3D%27userSpaceOnUse%27%3E%3Cstop%20stop-color%3D%27%2300e5ff%27/%3E%3Cstop%20offset%3D%271%27%20stop-color%3D%27%23b026ff%27/%3E%3C/linearGradient%3E%3C/defs%3E%3Cpath%20d%3D%27M32%204%20L55.5%2012.5%20V28%20C55.5%2042.5%2046%2052.5%2032%2059.5%20C18%2052.5%208.5%2042.5%208.5%2028%20V12.5%20Z%27%20fill%3D%27url%28%23g%29%27%20fill-opacity%3D%270.15%27/%3E%3Cpath%20d%3D%27M32%204%20L55.5%2012.5%20V28%20C55.5%2042.5%2046%2052.5%2032%2059.5%20C18%2052.5%208.5%2042.5%208.5%2028%20V12.5%20Z%27%20stroke%3D%27url%28%23g%29%27%20stroke-width%3D%273.4%27%20stroke-linejoin%3D%27round%27%20fill%3D%27none%27/%3E%3Cpath%20d%3D%27M22%2046.5%20V29%20C22%2021.8%2026.4%2016%2032%2016%20C37.6%2016%2042%2021.8%2042%2029%20V46.5%27%20stroke%3D%27url%28%23g%29%27%20stroke-width%3D%272.6%27%20stroke-linecap%3D%27round%27%20fill%3D%27none%27/%3E%3Cpath%20d%3D%27M28%2046.5%20V31.5%20C28%2027%2029.7%2023.5%2032%2023.5%20C34.3%2023.5%2036%2027%2036%2031.5%20V46.5%27%20stroke%3D%27url%28%23g%29%27%20stroke-width%3D%272%27%20stroke-linecap%3D%27round%27%20fill%3D%27none%27%20opacity%3D%270.6%27/%3E%3Ccircle%20cx%3D%2732%27%20cy%3D%2736.5%27%20r%3D%273%27%20fill%3D%27url%28%23g%29%27/%3E%3C/svg%3E">
<title>{% block title %}{{ t.brand }}{% endblock %}</title>
<style>
:root{
  --bg-deep:#020203;
  --panel-bg:rgba(8,8,12,.7);
  --border-neon:rgba(0,229,255,.15);
  --neon-cyan:#00e5ff;
  --neon-purple:#b026ff;
  --btn-tx:#020203;
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
  background-attachment:fixed;transition:background-color .25s,color .25s}
[data-theme=light] body{background-color:#eef2f9;
  background-image:linear-gradient(to bottom right,#e3f0ff,#f6f9ff)}
::-webkit-scrollbar{width:6px;height:6px}
::-webkit-scrollbar-track{background:transparent}
::-webkit-scrollbar-thumb{background:var(--neon-cyan);border-radius:10px}
[data-theme=light] ::-webkit-scrollbar-thumb{background:#a3c3e0}
html[dir=ltr] body{font-family:system-ui,-apple-system,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif}
html[dir=ltr] .gheading{letter-spacing:3px}
.container{max-width:1180px;margin:0 auto;padding:0 16px}
header{background:var(--panel-bg);backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);
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
.card{background:var(--panel-bg);border:1px solid var(--border-neon);border-radius:20px;
  padding:20px;margin-bottom:16px;backdrop-filter:blur(15px);-webkit-backdrop-filter:blur(15px);
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
  background:var(--card3);border:1px solid var(--bd);flex:none}
.stat-label{color:var(--mu);font-size:.82rem;font-weight:600}
.stat b{font-size:1.05rem;word-break:break-all}
.btn{border:1px solid rgba(255,255,255,.08);background:var(--card2);color:var(--tx);
  border-radius:10px;padding:9px 16px;cursor:pointer;font-family:inherit;font-size:.87rem;
  font-weight:600;transition:all .18s;text-decoration:none;display:inline-flex;align-items:center;gap:6px}
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
.icon-btn{background:none;border:none;cursor:pointer;font-size:.92rem;padding:3px 5px;opacity:.75;
  transition:all .15s;border-radius:6px}
.icon-btn:hover{opacity:1;transform:scale(1.12)}
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
.ctrl-cluster{position:fixed;bottom:18px;inset-inline-end:18px;z-index:100;display:flex;gap:9px}
.ctrl-btn{width:44px;height:44px;border-radius:14px;display:grid;place-items:center;font-size:1.1rem;
  border:1px solid var(--bd2);background:var(--panel-bg);backdrop-filter:blur(15px);color:var(--tx);
  cursor:pointer;text-decoration:none;font-family:inherit;font-weight:700;box-shadow:var(--sh2);transition:all .18s}
.ctrl-btn:hover{transform:translateY(-3px);border-color:var(--neon-cyan);box-shadow:0 0 18px rgba(0,229,255,.25)}
.bar{height:5px;background:rgba(255,255,255,.06);border-radius:99px;overflow:hidden;margin-top:6px;min-width:95px}
[data-theme=light] .bar{background:#e2e8f4}
.bar-fill{height:100%;border-radius:99px;background:linear-gradient(90deg,var(--neon-cyan),var(--neon-purple));
  box-shadow:0 0 12px rgba(0,229,255,.4);transition:width .6s ease}
.bar-fill.warn{background:linear-gradient(90deg,#f59e0b,#f97316);box-shadow:0 0 12px rgba(245,158,11,.4)}
.bar-fill.danger{background:linear-gradient(90deg,#ef4444,#dc2626);box-shadow:0 0 12px rgba(239,68,68,.4)}
.traffic-cell{display:flex;flex-direction:column;min-width:110px}
/* ===== logo (L2TP tunnel shield) ===== */
.lg-a{stop-color:var(--neon-cyan)}
.lg-b{stop-color:var(--neon-purple)}
.logo-svg{display:block;filter:drop-shadow(0 0 6px color-mix(in srgb,var(--neon-cyan) 45%,transparent))}
[data-theme=light] .logo-svg{filter:drop-shadow(0 0 5px color-mix(in srgb,var(--acc) 30%,transparent))}
.logo-svg circle{animation:lgpulse 2.6s ease-in-out infinite}
@keyframes lgpulse{0%,100%{opacity:1}50%{opacity:.4}}
.login-logo{width:66px;height:66px;border-radius:19px;display:grid;place-items:center;margin:0 auto 12px;
  background:var(--card3);border:1px solid var(--bd2);box-shadow:0 0 20px rgba(0,229,255,.22)}
.login-logo .logo-svg{width:44px;height:44px}
@media(max-width:600px){h1{font-size:.95rem}.card{padding:16px}}
/* ===== aura cursor ===== */
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
</style>
</head>
<body>
<div class="ctrl-cluster">
  <button type="button" class="ctrl-btn" id="themeBtn" onclick="toggleTheme()" title="{{ t.theme_tip }}">&#127769;</button>
  <a class="ctrl-btn" href="/lang/{{ 'en' if lang == 'fa' else 'fa' }}" title="{{ lang|upper }}">{{ 'EN' if lang == 'fa' else 'FA' }}</a>
</div>
{% block body %}{% endblock %}
<script>
function applyThemeBtn(){
  var cur=document.documentElement.getAttribute('data-theme')||'dark';
  var b=document.getElementById('themeBtn');
  if(b){b.textContent = (cur==='dark') ? '\u2600\uFE0F' : '\uD83C\uDF19';}
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
document.querySelectorAll('.reveal').forEach(function(b){b.addEventListener('click',function(){var s=b.parentElement.querySelector('.pw');if(s.getAttribute('data-shown')==='1'){s.textContent='\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022';s.setAttribute('data-shown','0');b.textContent='\uD83D\uDC41';}else{s.textContent=s.getAttribute('data-pw');s.setAttribute('data-shown','1');b.textContent='\uD83D\uDE48';}});});
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
TPL_BASE_HTML

cat > ${PANEL_DIR}/templates/login.html <<'TPL_LOGIN_HTML'
{% extends 'base.html' %}
{% block title %}{{ t.login_title }}{% endblock %}
{% block body %}
<style>
.gcard{width:100%;max-width:400px;border-radius:22px;padding:2px;
  background-image:linear-gradient(163deg,#00ff75 0%,#3700ff 100%);transition:all .3s}
.gcard:hover{box-shadow:0 0 30px 1px rgba(0,255,117,.3)}
.gform{background-color:#171717;border-radius:20px;transition:all .2s;
  padding:12px 2em 1.4em;display:flex;flex-direction:column}
.gcard:hover .gform{transform:scale(.98);border-radius:18px}
.gheading{text-align:center;margin:1.2em 1em 1em;color:#fff;font-size:1.15em;font-weight:700}
.gsub{text-align:center;color:#666;font-size:.72rem;margin:-0.8em 0 .4em}
.gfield{display:flex;align-items:center;justify-content:center;gap:.6em;
  border-radius:25px;padding:.7em 1em;border:none;outline:none;color:#fff;
  background-color:#171717;box-shadow:inset 2px 5px 10px rgb(5,5,5);margin-top:12px;
  transition:box-shadow .25s}
.gfield:focus-within{box-shadow:inset 2px 5px 10px rgb(5,5,5),0 0 0 2px rgba(0,255,117,.4)}
.gicon{height:1.3em;width:1.3em;fill:#9a9a9a;flex:none;transition:fill .25s}
.gfield:focus-within .gicon{fill:#00ff75}
.gfield input{background:none;border:none;outline:none;width:100%;color:#d3d3d3;
  font-family:inherit;font-size:.9rem}
.gfield input::placeholder{color:#6f6f6f}
.gbtn-row{display:flex;justify-content:center;margin-top:1.8em}
.gbtn{padding:.75em 2.5em;border-radius:6px;border:none;outline:none;cursor:pointer;
  transition:.4s ease-in-out;background-color:#252525;color:#fff;width:100%;
  font-family:inherit;font-weight:600;font-size:.9rem}
.gbtn:hover{background-color:#000;color:#fff}
.gerr{background:rgba(255,60,60,.12);color:#ff7b7b;border:1px solid rgba(255,60,60,.35);
  padding:.7em 1em;border-radius:12px;margin:1em 0 .2em;font-size:.83rem;
  font-weight:600;text-align:center}
[data-theme=light] .gcard{background-image:none;padding:0;
  background:linear-gradient(to right,#ffffff,#f8f9fd);
  border:5px solid #ffffff;border-radius:40px;
  box-shadow:rgba(133,189,215,.878) 0 30px 30px -20px}
[data-theme=light] .gcard:hover{box-shadow:rgba(133,189,215,.878) 0 34px 34px -22px}
[data-theme=light] .gform{background:transparent;border-radius:35px;
  padding:25px 35px;transform:none !important}
[data-theme=light] .gheading{color:rgb(70,130,180);font-weight:900;font-size:1.6rem}
[data-theme=light] .gsub{color:#7a93ad}
[data-theme=light] .gfield{background:#fff;border-inline:2px solid transparent;
  box-shadow:#cff0ff 0 10px 10px -5px}
[data-theme=light] .gfield:focus-within{border-inline:2px solid #12b1d1;
  box-shadow:#cff0ff 0 10px 10px -5px}
[data-theme=light] .gicon{fill:#8fa8bd}
[data-theme=light] .gfield input{color:#182238}
[data-theme=light] .gfield input::placeholder{color:#9aa8b8}
[data-theme=light] .gbtn{background:linear-gradient(to right,#0b98ec,#0f58e8);
  border-radius:20px;box-shadow:rgba(133,189,215,.878) 0 20px 10px -15px}
[data-theme=light] .gbtn:hover{transform:scale(1.03);
  background:linear-gradient(to right,#0b98ec,#0f58e8)}
[data-theme=light] .gerr{background:#fef2f2;color:#b91c1c;border-color:#fecaca}
[data-theme=light] .gfield input:-webkit-autofill{
  -webkit-box-shadow:0 0 0 1000px #ffffff inset;-webkit-text-fill-color:#182238}
</style>
<div class="login-wrap">
  <form method="post" class="gcard">
    <div class="gform">
      <div class="login-logo">
        <svg class="logo-svg" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="L2TP">
          <defs><linearGradient id="lgl" x1="10" y1="6" x2="54" y2="58" gradientUnits="userSpaceOnUse">
            <stop class="lg-a" offset="0"/><stop class="lg-b" offset="1"/></linearGradient></defs>
          <path d="M32 4 L55.5 12.5 V28 C55.5 42.5 46 52.5 32 59.5 C18 52.5 8.5 42.5 8.5 28 V12.5 Z" stroke="url(#lgl)" stroke-width="3.4" stroke-linejoin="round" fill="url(#lgl)" fill-opacity="0.08"/>
          <path d="M22 46.5 V29 C22 21.8 26.4 16 32 16 C37.6 16 42 21.8 42 29 V46.5" stroke="url(#lgl)" stroke-width="2.6" stroke-linecap="round"/>
          <path d="M28 46.5 V31.5 C28 27 29.7 23.5 32 23.5 C34.3 23.5 36 27 36 31.5 V46.5" stroke="url(#lgl)" stroke-width="2" stroke-linecap="round" opacity="0.6"/>
          <circle cx="32" cy="36.5" r="3" fill="url(#lgl)"/>
        </svg>
      </div>
      <div class="gheading">{{ t.brand }}</div>
      <div class="gsub">L2TP / IPSec PSK</div>
      {% if error %}<div class="gerr">{{ error }}</div>{% endif %}
      <div class="gfield">
        <svg class="gicon" viewBox="0 0 24 24"><path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/></svg>
        <input type="text" name="username" placeholder="{{ t.username }}" autofocus required autocomplete="username">
      </div>
      <div class="gfield">
        <svg class="gicon" viewBox="0 0 24 24"><path d="M18 8h-1V6c0-2.76-2.24-5-5-5S7 3.24 7 6v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2zm-6 9c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2zm3.1-9H8.9V6c0-1.71 1.39-3.1 3.1-3.1s3.1 1.39 3.1 3.1v2z"/></svg>
        <input type="password" name="password" placeholder="{{ t.password }}" required autocomplete="current-password">
      </div>
      <div class="gbtn-row">
        <button type="submit" class="gbtn">{{ t.login_btn }}</button>
      </div>
    </div>
  </form>
</div>
{% endblock %}

TPL_LOGIN_HTML

cat > ${PANEL_DIR}/templates/index.html <<'TPL_INDEX_HTML'
{% extends 'base.html' %}
{% block title %}{{ t.header_title }}{% endblock %}
{% block body %}
<style>
.ver-badge{display:inline-block;vertical-align:middle;font-size:.62rem;font-weight:700;
  padding:2px 9px;border-radius:99px;margin-inline-start:8px;letter-spacing:.5px;
  background:var(--card3);border:1px solid var(--bd2);color:var(--mu);
  -webkit-text-fill-color:var(--mu)}
.svc-row{display:flex;gap:8px;flex-wrap:wrap}
.svc{padding:5px 13px;border-radius:9px;font-size:.76rem;font-weight:700}
.svc.ok{background:rgba(52,211,153,.13);color:var(--grn)}
.svc.bad{background:rgba(248,113,113,.13);color:var(--red)}
[data-theme=light] .svc.ok{background:#dcfce7;color:#15803d}
[data-theme=light] .svc.bad{background:#fee2e2;color:#b91c1c}
</style>
<header>
  <div class="container header-in">
    <div class="brand">
      <div class="brand-badge"><svg class="logo-svg" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="L2TP"><defs><linearGradient id="lgh" x1="10" y1="6" x2="54" y2="58" gradientUnits="userSpaceOnUse"><stop class="lg-a" offset="0"/><stop class="lg-b" offset="1"/></linearGradient></defs><path d="M32 4 L55.5 12.5 V28 C55.5 42.5 46 52.5 32 59.5 C18 52.5 8.5 42.5 8.5 28 V12.5 Z" stroke="url(#lgh)" stroke-width="3.4" stroke-linejoin="round" fill="url(#lgh)" fill-opacity="0.08"/><path d="M22 46.5 V29 C22 21.8 26.4 16 32 16 C37.6 16 42 21.8 42 29 V46.5" stroke="url(#lgh)" stroke-width="2.6" stroke-linecap="round"/><path d="M28 46.5 V31.5 C28 27 29.7 23.5 32 23.5 C34.3 23.5 36 27 36 31.5 V46.5" stroke="url(#lgh)" stroke-width="2" stroke-linecap="round" opacity="0.6"/><circle cx="32" cy="36.5" r="3" fill="url(#lgh)"/></svg></div>
      <h1>{{ t.header_title }} <span class="ver-badge">v{{ panel_version }}</span></h1>
    </div>
    <div class="actions">
      <form method="post" action="/sync" class="inline"><button class="btn small">{{ t.sync_btn }}</button></form>
      <form method="post" action="/update" class="inline" onsubmit="return confirm('{{ t.update_confirm }}')">
        <button class="btn small">{{ t.update_btn }}</button>
      </form>
      <form method="post" action="/restart-vpn" class="inline" onsubmit="return confirm('{{ t.restart_vpn_confirm }}')">
        <button class="btn small">{{ t.restart_vpn_btn }}</button>
      </form>
      <form method="post" action="/restart-panel" class="inline" onsubmit="return confirm('{{ t.restart_panel_confirm }}')">
        <button class="btn small">{{ t.restart_panel_btn }}</button>
      </form>
      <a class="btn small" href="/logout">{{ t.logout_btn }}</a>
    </div>
  </div>
</header>

<main class="container">
  {% with msgs = get_flashed_messages() %}
    {% for m in msgs %}<div class="alert ok">{{ m }}</div>{% endfor %}
  {% endwith %}

  <section class="cards">
    <div class="card stat">
      <div class="stat-head"><span class="stat-icon">ðŸŒ</span><span class="stat-label">{{ t.server_address }}</span></div>
      <div class="secret-row"><b class="pw">{{ server_ip }}</b>
        <button type="button" class="icon-btn copy-btn" data-copy="{{ server_ip }}" title="{{ t.copy_tip }}">ðŸ“‹</button></div>
    </div>
    <div class="card stat">
      <div class="stat-head"><span class="stat-icon">ðŸ”‘</span><span class="stat-label">{{ t.psk_label }}</span></div>
      <div class="secret-row">
        <span class="pw" data-pw="{{ psk }}" data-shown="0">â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢</span>
        <button type="button" class="icon-btn reveal" title="{{ t.show_tip }}">ðŸ‘</button>
        <button type="button" class="icon-btn copy-btn" data-copy="{{ psk }}" title="{{ t.copy_tip }}">ðŸ“‹</button>
      </div>
    </div>
    <div class="card stat">
      <div class="stat-head"><span class="stat-icon">ðŸ‘¤</span><span class="stat-label">{{ t.active_users }}</span></div>
      <b>{{ active_count }} {{ t.of_word }} {{ total_count }}</b>
    </div>
    <div class="card stat">
      <div class="stat-head"><span class="stat-icon">ðŸ“¡</span><span class="stat-label">{{ t.online_sessions }}</span></div>
      <b>{{ online_count }}</b>
    </div>
    <div class="card stat">
      <div class="stat-head"><span class="stat-icon">âš™ï¸</span><span class="stat-label">{{ t.services_status }}</span></div>
      <div class="svc-row">
        <span class="svc {{ 'ok' if svc.ipsec else 'bad' }}">IPSec</span>
        <span class="svc {{ 'ok' if svc.xl2tpd else 'bad' }}">L2TP</span>
        <span class="svc {{ 'ok' if svc.nat else 'bad' }}">NAT</span>
      </div>
    </div>
  </section>

  <section class="card">
    <h2>{{ t.add_user_title }}</h2>
    <form method="post" action="/add" class="add-form">
      <div>
        <label>{{ t.username }}</label>
        <input name="username" required pattern="[A-Za-z0-9_.\-]{3,32}" placeholder="user01">
      </div>
      <div>
        <label>{{ t.password_auto }}</label>
        <div class="secret-row" style="width:100%">
          <input name="password" id="pw-input" placeholder="{{ t.auto_placeholder }}" style="flex:1">
          <button type="button" class="btn small" onclick="genPass()">ðŸŽ²</button>
        </div>
      </div>
      <div>
        <label>{{ t.days_label }}</label>
        <input type="number" name="days" value="30" min="1" max="3650">
      </div>
      <div>
        <label>{{ t.traffic_label }}</label>
        <input type="number" name="traffic" min="0" step="0.1" placeholder="{{ t.traffic_ph }}">
      </div>
      <div>
        <label>{{ t.dns1_label }}</label>
        <input name="dns1" placeholder="8.8.8.8" inputmode="numeric">
      </div>
      <div>
        <label>{{ t.dns2_label }}</label>
        <input name="dns2" placeholder="1.1.1.1" inputmode="numeric">
      </div>
      <div>
        <label>{{ t.exact_expiry }}</label>
        <input type="datetime-local" name="expires_at">
      </div>
      <div class="full">
        <button class="btn primary">ï¼‹ {{ t.add_btn }}</button>
        <span class="muted">{{ t.exact_note }}</span>
      </div>
    </form>
  </section>

  <section class="card">
    <h2>{{ t.users_title }}</h2>
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>#</th><th>{{ t.th_username }}</th><th>{{ t.th_password }}</th><th>{{ t.th_expiry }}</th>
            <th>{{ t.th_remaining }}</th><th>{{ t.th_traffic }}</th><th>{{ t.th_dns }}</th><th>{{ t.th_key }}</th>
            <th>{{ t.th_status }}</th><th>{{ t.th_actions }}</th>
          </tr>
        </thead>
        <tbody>
        {% for u in users %}
          <tr class="{{ 'expired' if (u.expired or u.quota_exceeded) else '' }}">
            <td>{{ loop.index }}</td>
            <td><b>{{ u.username }}</b>{% if u.online %}<span class="dot" title="{{ t.online_tip }}"></span>{% endif %}</td>
            <td>
              <span class="secret-row">
                <span class="pw" data-pw="{{ u.password }}" data-shown="0">â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢</span>
                <button type="button" class="icon-btn reveal" title="{{ t.show_tip }}">ðŸ‘</button>
                <button type="button" class="icon-btn copy-btn" data-copy="{{ u.password }}" title="{{ t.copy_tip }}">ðŸ“‹</button>
              </span>
            </td>
            <td>{{ u.expires }}</td>
            <td>{{ u.remaining }}</td>
            <td>
              <div class="traffic-cell">
                <span>{{ u.traffic }}</span>
                {% if u.limit_gb > 0 %}
                <div class="bar"><div class="bar-fill {{ 'danger' if u.traffic_pct >= 90 else ('warn' if u.traffic_pct >= 70 else '') }}" style="width: {{ u.traffic_pct }}%"></div></div>
                {% endif %}
              </div>
            </td>
            <td>
              {% if u.dns1 or u.dns2 %}
                <span class="pw">{{ u.dns1 or 'â€”' }} / {{ u.dns2 or 'â€”' }}</span>
              {% else %}
                <span class="muted">{{ t.default_dns }}</span>
              {% endif %}
            </td>
            <td>
              <span class="secret-row">
                <span class="pw">{{ u.key }}</span>
                <button type="button" class="icon-btn copy-btn" data-copy="{{ u.key }}" title="{{ t.copy_tip }}">ðŸ“‹</button>
                <a class="icon-btn" href="/u/{{ u.key }}" target="_blank" title="{{ t.status_link_tip }}">ðŸ”—</a>
              </span>
            </td>
            <td>
              {% if u.expired %}<span class="badge red">{{ t.badge_expired }}</span>
              {% elif u.quota_exceeded %}<span class="badge red">{{ t.badge_quota }}</span>
              {% elif u.soon %}<span class="badge orange">{{ t.badge_soon }}</span>
              {% else %}<span class="badge green">{{ t.badge_active }}</span>{% endif %}
            </td>
            <td>
              <form method="post" action="/renew/{{ u.id }}" class="inline">
                <input class="mini" type="number" name="days" value="30" min="1" max="3650">
                <button class="btn small">{{ t.renew_btn }}</button>
              </form>
              <button class="btn small" onclick="openEdit({{ u.id }}, '{{ u.expires_input }}', '{{ u.dns1 }}', '{{ u.dns2 }}', '{{ u.key }}')">âœï¸</button>
              <form method="post" action="/reset-traffic/{{ u.id }}" class="inline">
                <button class="btn small" title="{{ t.reset_traffic_tip }}">â™»ï¸</button>
              </form>
              <form method="post" action="/regen-key/{{ u.id }}" class="inline">
                <button class="btn small" title="{{ t.regen_key_tip }}">ðŸ”‘</button>
              </form>
              <form method="post" action="/delete/{{ u.id }}" class="inline" onsubmit="return confirm('{{ t.delete_confirm }}')">
                <button class="btn small danger">ðŸ—‘</button>
              </form>
            </td>
          </tr>
        {% else %}
          <tr><td colspan="10" class="empty">{{ t.no_users }}</td></tr>
        {% endfor %}
        </tbody>
      </table>
    </div>
  </section>
</main>

<div class="modal" id="editModal">
  <form method="post" id="editForm" class="modal-card">
    <h3>âœï¸ {{ t.edit_title }}</h3>
    <label>{{ t.new_password }}</label>
    <input name="password" id="editPass">
    <label>{{ t.new_expiry }}</label>
    <input type="datetime-local" name="expires_at" id="editExp">
    <label>{{ t.new_traffic }}</label>
    <input type="number" step="0.1" min="0" name="traffic" id="editTraffic">
    <label>{{ t.new_dns1 }}</label>
    <input name="dns1" id="editDns1" placeholder="8.8.8.8" inputmode="numeric">
    <label>{{ t.new_dns2 }}</label>
    <input name="dns2" id="editDns2" placeholder="1.1.1.1" inputmode="numeric">
    <label>{{ t.new_key }}</label>
    <input name="key" id="editKey">
    <div class="modal-btns">
      <button type="button" class="btn" onclick="closeEdit()">{{ t.cancel }}</button>
      <button type="submit" class="btn primary">{{ t.save }}</button>
    </div>
  </form>
</div>
{% endblock %}

{% block scripts %}
<script>
function openEdit(id, exp, dns1, dns2, key){
  document.getElementById('editForm').action = '/edit/' + id;
  document.getElementById('editExp').value = exp;
  document.getElementById('editPass').value = '';
  document.getElementById('editTraffic').value = '';
  document.getElementById('editDns1').value = dns1;
  document.getElementById('editDns2').value = dns2;
  document.getElementById('editKey').value = key;
  document.getElementById('editModal').classList.add('show');
}
function closeEdit(){ document.getElementById('editModal').classList.remove('show'); }
document.getElementById('editModal').addEventListener('click', function(e){ if(e.target === this) closeEdit(); });
document.addEventListener('keydown', function(e){ if(e.key === 'Escape') closeEdit(); });
</script>
{% endblock %}

TPL_INDEX_HTML

cat > ${PANEL_DIR}/templates/user.html <<'TPL_USER_HTML'
{% extends 'base.html' %}
{% block title %}{{ t.status_title }}{% endblock %}
{% block body %}
<style>
.sub-wrap{min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px 16px}
.sub-card{width:100%;max-width:480px;animation:subIn .5s ease}

/* ---- status banner (logo + status text) ---- */
.status-banner{display:flex;align-items:center;gap:16px;padding:16px 20px;border-radius:18px;
  margin-bottom:18px;border:1px solid}
.status-banner.active{background:rgba(0,255,157,.07);border-color:rgba(0,255,157,.35);
  box-shadow:0 0 24px rgba(0,255,157,.12)}
.status-banner.expired{background:rgba(255,77,109,.07);border-color:rgba(255,77,109,.35);
  box-shadow:0 0 24px rgba(255,77,109,.12)}
.status-banner.quota{background:rgba(255,176,32,.07);border-color:rgba(255,176,32,.35);
  box-shadow:0 0 24px rgba(255,176,32,.12)}
[data-theme=light] .status-banner.active{background:#f0fdf4;border-color:#bbf7d0;box-shadow:none}
[data-theme=light] .status-banner.expired{background:#fef2f2;border-color:#fecaca;box-shadow:none}
[data-theme=light] .status-banner.quota{background:#fffbeb;border-color:#fde68a;box-shadow:none}
.sub-logo{width:56px;height:56px;border-radius:17px;display:grid;place-items:center;flex:none;
  background:var(--card3);border:1px solid var(--bd2);box-shadow:0 0 18px rgba(0,229,255,.2)}
.sub-logo .logo-svg{width:37px;height:37px}
.sb-text{flex:1;min-width:0;display:flex;flex-direction:column;gap:4px}
.sb-title{font-weight:800;font-size:1.06rem}
.sb-sub{font-size:.86rem;color:var(--mu)}

/* ---- gauge zone ---- */
.gauge-zone{display:flex;align-items:center;justify-content:space-between;gap:16px;
  padding:8px 24px 4px}
.gauge{position:relative;width:150px;height:150px;flex:none}
.gauge svg{transform:rotate(-90deg)}
.gauge .g-bg{fill:none;stroke:rgba(255,255,255,.07);stroke-width:11}
[data-theme=light] .gauge .g-bg{stroke:#e5eaf4}
.gauge .g-fill{fill:none;stroke:url(#gaugeGrad);stroke-width:11;stroke-linecap:round;
  transition:stroke-dashoffset 1.2s cubic-bezier(.22,1,.36,1)}
.gauge .g-fill.warn{stroke:url(#gaugeWarn)}
.gauge .g-fill.danger{stroke:url(#gaugeDanger)}
.gauge-center{position:absolute;inset:0;display:flex;flex-direction:column;
  align-items:center;justify-content:center;text-align:center}
.gauge-center b{font-size:1.5rem;font-weight:800;
  background:linear-gradient(90deg,var(--neon-cyan),var(--neon-purple));
  -webkit-background-clip:text;background-clip:text;-webkit-text-fill-color:transparent}
.gauge-center span{font-size:.68rem;color:var(--mu);margin-top:3px}

.gauge-side{flex:1;min-width:0;display:flex;flex-direction:column;gap:12px}
.mini-stat{background:var(--card3);border:1px solid var(--bd);border-radius:14px;
  padding:12px 14px;overflow:hidden}
.mini-stat .ms-label{font-size:.7rem;color:var(--mu);font-weight:700;margin-bottom:7px;
  display:flex;align-items:center;gap:6px}
.mini-stat .ms-value{font-size:1.02rem;font-weight:700;word-break:break-word}
.mini-stat .ms-value.pw{font-weight:400}

/* ---- countdown (compact single row) ---- */
.countdown{display:flex;flex-wrap:nowrap;gap:4px;margin-top:2px;align-items:stretch}
.cd-box{flex:1 1 0;min-width:0;background:var(--bg-deep);
  border:1px solid var(--bd);border-radius:9px;padding:6px 2px;text-align:center}
[data-theme=light] .cd-box{background:var(--card2)}
.cd-box b{display:block;font-size:.84rem;font-weight:800;font-variant-numeric:tabular-nums;
  overflow:hidden;text-overflow:ellipsis;white-space:nowrap;line-height:1.2}
.cd-box span{display:block;font-size:.52rem;color:var(--mu);line-height:1.4;margin-top:2px}

/* ---- divider ---- */
.sub-divider{display:flex;align-items:center;gap:12px;padding:16px 24px 6px}
.sub-divider::before,.sub-divider::after{content:'';flex:1;height:1px;
  background:linear-gradient(90deg,transparent,var(--bd2),transparent)}
.sub-divider span{font-size:.72rem;color:var(--mu);letter-spacing:1.5px;font-weight:700}

/* ---- info rows ---- */
.sub-info{padding:4px 24px 10px}
.info-row{display:flex;justify-content:space-between;align-items:center;gap:12px;
  padding:12px 0;border-bottom:1px dashed var(--bd)}
.info-row:last-child{border-bottom:none}
.info-row>span{color:var(--mu);font-size:.82rem;font-weight:600;flex:none}
.info-row>div,.info-row>b{word-break:break-all;text-align:end;font-size:.9rem;min-width:0}

.sub-footer{padding:12px 24px 20px;text-align:center}
.sub-footer .muted{font-size:.72rem}

@keyframes subIn{from{opacity:0;transform:translateY(14px) scale(.98)}to{opacity:1;transform:none}}

@media(max-width:430px){
  .gauge-zone{flex-direction:column}
  .gauge-side{width:100%}
}
</style>

<!-- shared gradient defs -->
<svg width="0" height="0" style="position:absolute">
  <defs>
    <linearGradient id="gaugeGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" class="lg-a"/><stop offset="100%" class="lg-b"/>
    </linearGradient>
    <linearGradient id="gaugeWarn" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#f59e0b"/><stop offset="100%" stop-color="#f97316"/>
    </linearGradient>
    <linearGradient id="gaugeDanger" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#ef4444"/><stop offset="100%" stop-color="#dc2626"/>
    </linearGradient>
    <linearGradient id="lgu" x1="10" y1="6" x2="54" y2="58" gradientUnits="userSpaceOnUse">
      <stop class="lg-a" offset="0"/><stop class="lg-b" offset="1"/>
    </linearGradient>
  </defs>
</svg>

<div class="sub-wrap">
  <div class="card sub-card">

    {% set pct = u.traffic_pct %}
    {% set CIRC = 314 %}

    <div class="status-banner {{ 'expired' if u.expired else ('quota' if u.quota_exceeded else 'active') }}">
      <div class="sub-logo">
        <svg class="logo-svg" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="L2TP"><path d="M32 4 L55.5 12.5 V28 C55.5 42.5 46 52.5 32 59.5 C18 52.5 8.5 42.5 8.5 28 V12.5 Z" stroke="url(#lgu)" stroke-width="3.4" stroke-linejoin="round" fill="url(#lgu)" fill-opacity="0.08"/><path d="M22 46.5 V29 C22 21.8 26.4 16 32 16 C37.6 16 42 21.8 42 29 V46.5" stroke="url(#lgu)" stroke-width="2.6" stroke-linecap="round"/><path d="M28 46.5 V31.5 C28 27 29.7 23.5 32 23.5 C34.3 23.5 36 27 36 31.5 V46.5" stroke="url(#lgu)" stroke-width="2" stroke-linecap="round" opacity="0.6"/><circle cx="32" cy="36.5" r="3" fill="url(#lgu)"/></svg>
      </div>
      <div class="sb-text">
        <span class="sb-title">{{ t.badge_expired if u.expired else (t.badge_quota if u.quota_exceeded else t.badge_active) }}</span>
        <span class="sb-sub">{{ u.username }} Â· L2TP/IPSec</span>
      </div>
    </div>

    <div class="gauge-zone">
      <div class="gauge">
        <svg width="150" height="150" viewBox="0 0 150 150">
          <circle class="g-bg" cx="75" cy="75" r="52"/>
          <circle class="g-fill {{ 'danger' if pct >= 90 else ('warn' if pct >= 70 else '') }}"
                  cx="75" cy="75" r="52"
                  stroke-dasharray="{{ CIRC }}"
                  stroke-dashoffset="{{ CIRC - (CIRC * pct / 100) if u.limit_gb > 0 else CIRC }}"/>
        </svg>
        <div class="gauge-center">
          {% if u.limit_gb > 0 %}
            <b>{{ pct }}%</b>
          {% else %}
            <b>âˆž</b>
          {% endif %}
          <span>{{ u.traffic }}</span>
        </div>
      </div>

      <div class="gauge-side">
        <div class="mini-stat">
          <div class="ms-label">â± {{ t.st_remaining }}</div>
          {% if u.expired or u.quota_exceeded %}
            <div class="ms-value muted">â€”</div>
          {% else %}
            <div class="countdown" id="liveCountdown" data-expires="{{ u.expires }}">
              <div class="cd-box"><b id="cdD">â€”</b><span>{{ 'Ø±ÙˆØ²' if lang=='fa' else 'D' }}</span></div>
              <div class="cd-box"><b id="cdH">â€”</b><span>{{ 'Ø³Ø§Ø¹Øª' if lang=='fa' else 'H' }}</span></div>
              <div class="cd-box"><b id="cdM">â€”</b><span>{{ 'Ø¯Ù‚ÛŒÙ‚Ù‡' if lang=='fa' else 'M' }}</span></div>
              <div class="cd-box"><b id="cdS">â€”</b><span>{{ 'Ø«Ø§Ù†ÛŒÙ‡' if lang=='fa' else 'S' }}</span></div>
            </div>
          {% endif %}
        </div>
        <div class="mini-stat">
          <div class="ms-label">ðŸ“… {{ t.st_expiry }}</div>
          <div class="ms-value pw">{{ u.expires }}</div>
        </div>
      </div>
    </div>

    <div class="sub-divider"><span>{{ t.st_type }}</span></div>

    <div class="sub-info">
      <div class="info-row"><span>{{ t.st_server }}</span>
        <div class="secret-row"><b class="pw">{{ server_ip }}</b>
          <button type="button" class="icon-btn copy-btn" data-copy="{{ server_ip }}" title="{{ t.copy_tip }}">ðŸ“‹</button></div>
      </div>
      <div class="info-row"><span>{{ t.st_psk }}</span>
        <div class="secret-row">
          <span class="pw" data-pw="{{ psk }}" data-shown="0">â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢</span>
          <button type="button" class="icon-btn reveal" title="{{ t.show_tip }}">ðŸ‘</button>
          <button type="button" class="icon-btn copy-btn" data-copy="{{ psk }}" title="{{ t.copy_tip }}">ðŸ“‹</button>
        </div>
      </div>
      <div class="info-row"><span>{{ t.username }}</span>
        <div class="secret-row"><b class="pw">{{ u.username }}</b>
          <button type="button" class="icon-btn copy-btn" data-copy="{{ u.username }}" title="{{ t.copy_tip }}">ðŸ“‹</button></div>
      </div>
      <div class="info-row"><span>{{ t.password }}</span>
        <div class="secret-row">
          <span class="pw" data-pw="{{ u.password }}" data-shown="0">â€¢â€¢â€¢â€¢â€¢â€¢â€¢â€¢</span>
          <button type="button" class="icon-btn reveal" title="{{ t.show_tip }}">ðŸ‘</button>
          <button type="button" class="icon-btn copy-btn" data-copy="{{ u.password }}" title="{{ t.copy_tip }}">ðŸ“‹</button>
        </div>
      </div>
      <div class="info-row"><span>{{ t.st_dns }}</span>
        <b class="pw">{% if u.dns1 or u.dns2 %}{{ u.dns1 or 'â€”' }} / {{ u.dns2 or 'â€”' }}{% else %}{{ t.st_dns_default }}{% endif %}</b>
      </div>
    </div>

    <div class="sub-footer">
      <span class="muted">{{ t.brand }}</span>
    </div>
  </div>
</div>
{% endblock %}

{% block scripts %}
<script>
(function(){
  var el = document.getElementById('liveCountdown');
  if(!el) return;
  var target = new Date(el.getAttribute('data-expires').replace(' ','T')).getTime();
  function pad(n){return n<10?'0'+n:''+n;}
  function tick(){
    var diff = Math.max(0, target - Date.now());
    var d = Math.floor(diff/86400000),
        h = Math.floor(diff%86400000/3600000),
        m = Math.floor(diff%3600000/60000),
        s = Math.floor(diff%60000/1000);
    document.getElementById('cdD').textContent = d;
    document.getElementById('cdH').textContent = pad(h);
    document.getElementById('cdM').textContent = pad(m);
    document.getElementById('cdS').textContent = pad(s);
    if(diff <= 0){ clearInterval(timer); }
  }
  tick();
  var timer = setInterval(tick, 1000);
})();
</script>
{% endblock %}

TPL_USER_HTML

cat > ${PANEL_DIR}/templates/restarting.html <<'TPL_RESTARTING_HTML'
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


TPL_RESTARTING_HTML

cat > ${PANEL_DIR}/templates/updating.html <<'TPL_UPDATING_HTML'
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

TPL_UPDATING_HTML

cat > /etc/systemd/system/l2tp-panel.service <<'PANELSVC'
[Unit]
Description=3OUTHBOY PANEL Web UI
After=network.target

[Service]
WorkingDirectory=/opt/l2tp-panel
ExecStart=/usr/bin/gunicorn --workers 1 --threads 4 --bind 0.0.0.0:PANELPORT --timeout 60 panel:app
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
PANELSVC
sed -i "s/PANELPORT/${PANEL_PORT}/" /etc/systemd/system/l2tp-panel.service

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
  if [ -n "$ADMIN_IP" ]; then
    ufw allow from "$ADMIN_IP" to any port "$PANEL_PORT" proto tcp >/dev/null
  else
    ufw allow "${PANEL_PORT}/tcp" >/dev/null
  fi
  ufw route allow from 192.168.43.0/24 >/dev/null
  ufw route allow from 192.168.44.0/24 >/dev/null
  ufw --force enable >/dev/null
  ok "Firewall enabled"
fi

info "Starting services..."
systemctl daemon-reload
systemctl enable --now strongswan-starter >/dev/null 2>&1 || true
systemctl restart strongswan-starter
systemctl enable --now xl2tpd >/dev/null 2>&1 || true
systemctl restart xl2tpd
systemctl enable --now l2tp-nat >/dev/null 2>&1 || true
systemctl restart l2tp-nat
systemctl enable --now l2tp-panel >/dev/null 2>&1 || true
systemctl enable --now l2tp-sync.timer >/dev/null 2>&1 || true
python3 "${PANEL_DIR}/sync_users.py"
ok "All services started."

echo
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}      3OUTHBOY PANEL â€” Installation complete!        ${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo -e " Panel URL       : ${CYAN}http://${PUB_IP}:${PANEL_PORT}${NC}"
echo -e " Admin username  : ${CYAN}${ADMIN_USER}${NC}"
echo -e " Admin password  : ${CYAN}${ADMIN_PASS}${NC}"
echo -e " IPSec PSK       : ${CYAN}${PSK}${NC}"
echo -e " Client setup    : L2TP/IPSec PSK | Server: ${PUB_IP}"
echo -e " User status     : http://${PUB_IP}:${PANEL_PORT}/u/<USER_KEY>"
echo
warn "Save these credentials! (also in ${PANEL_DIR}/config.json)"
warn "Open UDP 500/4500/1701 + TCP ${PANEL_PORT} in provider firewall if any."
