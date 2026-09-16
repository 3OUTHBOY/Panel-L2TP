#!/bin/bash
# yt-adblock.sh — DNS-level ad blocker for VPN users (YouTube app included)
# Usage: yt-adblock.sh {on|off|update}
set -euo pipefail

MODE="${1:-}"
LIST_FILE="/etc/dnsmasq.d/adblock.list"
CONF_FILE="/etc/dnsmasq.d/adblock.conf"
LIST_URL="https://raw.githubusercontent.com/hagezi/dns-blocklists/main/dnsmasq/mini.txt"
YT_CORE=(ads.youtube.com ad.youtube.com youtube.cleverads.vn
  doubleclick.net googlesyndication.com google-analytics.com
  pubads.g.doubleclick.net securepubads.g.doubleclick.net
  googleads.g.doubleclick.net static.doubleclick.net
  pagead2.googlesyndication.com adservice.google.com
  imasdk.googleapis.com googleadservices.com googletagservices.com)
POOLS=("192.168.43.0/24" "192.168.44.0/24" "192.168.45.0/24")

fw() { /sbin/iptables -w 5 "$@" 2>/dev/null || true; }

build_list() {
  mkdir -p /etc/dnsmasq.d
  : > "${LIST_FILE}.tmp"
  URLS=(
    "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/dnsmasq/mini.txt"
    "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@main/dnsmasq/mini.txt"
    "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@main/dnsmasq/medium.txt"
    "https://dnsmasq.oisd.nl/"
  )
  for u in "${URLS[@]}"; do
    echo "[i] trying: $u"
    if timeout 40 curl -sfL --retry 1 "$u" -o "${LIST_FILE}.dl" && [ -s "${LIST_FILE}.dl" ]; then
      cat "${LIST_FILE}.dl" >> "${LIST_FILE}.tmp"; rm -f "${LIST_FILE}.dl"
      echo "[+] downloaded from: $u"
      break
    fi
  done
  echo "" >> "${LIST_FILE}.tmp"   # newline safety
  # bare domains → full NXDOMAIN (A+AAAA)
  for d in doubleclick.net googlesyndication.com google-analytics.com; do
    echo "local=/${d}/" >> "${LIST_FILE}.tmp"
  done
  for d in "${YT_CORE[@]}"; do
    echo "local=/${d}/" >> "${LIST_FILE}.tmp"
  done
  local N; N=$(grep -cE '^(address|local|server)=' "${LIST_FILE}.tmp" || true)
  if [ "$N" -gt 50 ]; then
    mv "${LIST_FILE}.tmp" "$LIST_FILE"
  else
    rm -f "${LIST_FILE}.tmp"
    [ -f "$LIST_FILE" ] || { echo "[X] no list available (offline?)"; exit 1; }
    echo "[i] using cached list"
  fi
}

apply_redirect() {
  for pool in "${POOLS[@]}"; do
    for proto in udp tcp; do
      if ! /sbin/iptables -w 5 -t nat -C PREROUTING -s "$pool" -p $proto --dport 53 -j REDIRECT --to-ports 53 2>/dev/null; then
        /sbin/iptables -w 5 -t nat -I PREROUTING -s "$pool" -p $proto --dport 53 -j REDIRECT --to-ports 53
      fi
    done
  done
}

remove_redirect() {
  for pool in "${POOLS[@]}"; do
    while iptables -w 5 -t nat -C PREROUTING -s "$pool" -p udp --dport 53 -j REDIRECT --to-ports 53 2>/dev/null; do
      fw -t nat -D PREROUTING -s "$pool" -p udp --dport 53 -j REDIRECT --to-ports 53
    done
    while iptables -w 5 -t nat -C PREROUTING -s "$pool" -p tcp --dport 53 -j REDIRECT --to-ports 53 2>/dev/null; do
      fw -t nat -D PREROUTING -s "$pool" -p tcp --dport 53 -j REDIRECT --to-ports 53
    done
  done
}

apply_dot() {
  for pool in "${POOLS[@]}"; do
    if ! /sbin/iptables -w 5 -C FORWARD -s "$pool" -p tcp --dport 853 -j DROP 2>/dev/null; then
      /sbin/iptables -w 5 -I FORWARD -s "$pool" -p tcp --dport 853 -j DROP
    fi
  done
}

remove_dot() {
  for pool in "${POOLS[@]}"; do
    while /sbin/iptables -w 5 -C FORWARD -s "$pool" -p tcp --dport 853 -j DROP 2>/dev/null; do
      /sbin/iptables -w 5 -D FORWARD -s "$pool" -p tcp --dport 853 -j DROP
    done
  done
}

case "$MODE" in
  on)
    dpkg -s dnsmasq >/dev/null 2>&1 || apt-get install -y dnsmasq >/dev/null
    grep -qE '^conf-dir=/etc/dnsmasq.d' /etc/dnsmasq.conf 2>/dev/null || echo 'conf-dir=/etc/dnsmasq.d' >> /etc/dnsmasq.conf
    build_list
    cat > "$CONF_FILE" <<'CONF'
listen-address=127.0.0.1
interface=ppp*
interface=tun*
interface=vpns*
bind-dynamic
no-resolv
server=1.1.1.1
server=8.8.8.8
cache-size=10000
CONF
    systemctl enable dnsmasq >/dev/null 2>&1 || true
    systemctl restart dnsmasq
    apply_redirect
    apply_dot
    ufw allow in on ppp+ to any port 53 proto udp >/dev/null 2>&1 || true
    ufw allow in on ppp+ to any port 53 proto tcp >/dev/null 2>&1 || true
    ufw allow in on tun+ to any port 53 proto udp >/dev/null 2>&1 || true
    ufw allow in on tun+ to any port 53 proto tcp >/dev/null 2>&1 || true
    ufw allow in on vpns+ to any port 53 proto udp >/dev/null 2>&1 || true
    ufw allow in on vpns+ to any port 53 proto tcp >/dev/null 2>&1 || true
    echo "done: adblock on ($(grep -cE '^(address|local|server)=' "$LIST_FILE") domains)"
    ;;
  off)
    remove_redirect
    remove_dot
    ufw delete allow in on ppp+ to any port 53 proto udp >/dev/null 2>&1 || true
    ufw delete allow in on ppp+ to any port 53 proto tcp >/dev/null 2>&1 || true
    ufw delete allow in on tun+ to any port 53 proto udp >/dev/null 2>&1 || true
    ufw delete allow in on tun+ to any port 53 proto tcp >/dev/null 2>&1 || true
    ufw delete allow in on vpns+ to any port 53 proto udp >/dev/null 2>&1 || true
    ufw delete allow in on vpns+ to any port 53 proto tcp >/dev/null 2>&1 || true
    /sbin/ipset destroy vpn_ads 2>/dev/null || true
    systemctl stop dnsmasq 2>/dev/null || true
    systemctl disable dnsmasq >/dev/null 2>&1 || true
    echo "done: adblock off"
    ;;
  update)
    build_list
    systemctl restart dnsmasq 2>/dev/null || true
    echo "done: adblock list updated"
    ;;
  *) echo "usage: $0 {on|off|update}"; exit 1 ;;
esac
