
3OUTHBOY PANEL
3OUTHBOY PANEL
English | فارسی

L2TP/IPSec VPN server with a modern web management panel — one-line install

UbuntuLicensePanelInstaller

Panel Dashboard | User Status Page

Panel Dashboard — neon cyberpunk themeUser status page — circular gauge, live countdown
📖 Table of Contents
Features
Quick Install
Installation Guide
Connecting Users
Panel Management
System Architecture
Troubleshooting
Uninstall
✨ Features
🔐 VPN Server
Feature	Details
L2TP/IPSec PSK	Works with Windows, Android, iOS and macOS — no extra app needed
strongSwan	curve25519 + modp1024 proposals for maximum compatibility (incl. iOS 17+)
192.168.43.x pool	Up to 240 concurrent users
XAuth (optional)	Cisco IPsec config for legacy clients
NAT + MSS Clamp	Full internet access with optimized MTU
👥 User Management
Feature	Details
Auto-expiry	Exact date & time + automatic disconnection of expired users
Traffic quota	Custom GB limit per user + real-time traffic counting (30s updates)
Custom DNS	Per-user DNS (Shecan, Electro, 403...) with transparent redirect
User key	Personal status page per user — no login required
Instant kick	Password change or user deletion = immediate disconnect
🖥️ Web Panel
Feature	Details
Bilingual	Persian (RTL) / English (LTR) with one click
Dark/Light theme	Neon cyberpunk theme + minimal light theme
Sidebar navigation	Slide-out menu — Dashboard / Users / Settings
Live dashboard	7-day traffic chart, top consumers, system capacity
Settings page	Change admin credentials, PSK, default DNS, panel port — all from the UI
Backup download	One-click full backup (users + settings)
Self-update	Update button syncs the latest version from GitHub in seconds
Neon SVG icons	Custom gradient icon set + glow cursor effect
🚀 Quick Install
Interactive mode (recommended)
On your Ubuntu server, as root or with sudo:

bash <(curl -Ls https://raw.githubusercontent.com/3OUTHBOY/Panel-L2TP/main/install.sh)
The installer asks a few questions:

Panel admin username and password
Panel port (your choice, default 8080)
PSK (default: secure auto-generated)
Allowed admin IP for panel access (optional)
Timezone and firewall
After ~2 minutes, connection info is displayed:

text

=====================================================
      3OUTHBOY PANEL — Installation complete!
=====================================================
 Panel URL       : http://YOUR_SERVER_IP:8080
 Admin username  : admin
 Admin password  : xK9mP2nQ8rT4
 IPSec PSK       : aB3cD4eF5gH6iJ7kL8mN
=====================================================
Unattended mode (for automation & cloud-init)
bash

bash <(curl -Ls https://raw.githubusercontent.com/3OUTHBOY/Panel-L2TP/main/install.sh) \
  --user admin \
  --pass MyStrongPass123 \
  --port 9443 \
  --psk MySecretPSK \
  --no-ufw
Flag
Default
Description
--user	admin	Admin username
--pass	random	Admin password
--port	8080	Panel port (user's choice)
--psk	random	IPSec pre-shared key
--admin-ip	empty	Allowed IP for panel (empty = no restriction)
--no-ufw	enabled	Skip UFW firewall setup

💡 We use bash <(curl ...) instead of curl | bash so interactive prompts (password/port/PSK) work correctly.

📱 Connecting Users
Windows
Settings → Network & Internet → VPN → Add a VPN connection
VPN provider: Windows (built-in)
Connection name: anything you like
Server name or address: server IP
VPN type: L2TP/IPsec with pre-shared key
Pre-shared key: copy from panel
Type of sign-in info: Username and password
Username / Password: from panel
If you get error 809: open UDP ports 500 and 4500 in Windows firewall and your router.

Android
Settings → Network & Internet → VPN → +
Name: anything
Type: L2TP/IPSec PSK
Server address: server IP
IPSec pre-shared key: from panel
Username / Password: from panel
iOS / macOS
Settings → VPN → Add VPN Configuration
Type: L2TP
Description: anything
Server: server IP
Account: username
Password: password
Secret: from panel
iOS 17+ automatically negotiates curve25519/modp1024 proposals — no special settings needed.

Linux (NetworkManager)
bash

nmcli connection add type vpn vpn-type l2tp \
  con-name "MyVPN" vpn.data "gateway=SERVER_IP, ipsec-enabled=yes, ipsec-psk=YOUR_PSK" \
  vpn.secrets "username=USER, password=PASS"
Panel Management
Navigation
The panel uses a slide-out sidebar (hamburger button) with three sections: Dashboard, Users and Settings.

Dashboard
Stat cards: server address, PSK (with show/copy buttons), active users, connected sessions, total traffic
7-day traffic chart with hover tooltips (fills up day by day)
Top consumers leaderboard with gold/silver/bronze medals
System capacity bar (IP slots used out of 240)
Service status: IPSec / L2TP / NAT — green = running, red = problem
Users
Add user: username, password (blank = auto-generate), validity (days), traffic limit (GB), primary/secondary DNS, exact expiry date
Users table: password (hidden/reveal), expiry, remaining time, traffic used (with colored progress bar), custom DNS, user key, status, actions
Per-user actions
Button
Action
Renew + days	Add days to user's expiry
Edit	Password, expiry date, quota, DNS, user key
Reset traffic	Zero the usage counter
New key	Generate new random key (old link becomes invalid)
Delete	Fully remove user + instant disconnect

User status link
Each user has a unique key. Give them this link:

text

http://SERVER_IP:PORT/u/USER_KEY
Without logging in, the user can see:

Full connection info (server, PSK, username/password, custom DNS)
Circular traffic gauge + live countdown (days/hours/minutes/seconds)
Status: active / expired / quota exceeded
⚠️ This link contains the VPN password — only share it with the user themself!

Settings
All manageable from the panel UI — no SSH needed:

Setting
Action
Admin account	Change panel username & password (requires current password)
PSK	Change IPSec pre-shared key (auto-restarts IPSec)
Default DNS	Server-wide DNS for users without custom DNS
Panel port	Change web port (auto firewall + redirect)
Backup	One-click download of all users & settings

Quick actions (header)
Sync: force user/quota/expiry sync
Update Panel: pull the latest version from GitHub (takes ~15 seconds, no re-login)
Restart VPN / Restart Panel
Language & theme
FA / EN chip (bottom corner): switch Persian ⇄ English
DARK / LIGHT chip: switch theme — your choice is saved in the browser
Recommended DNS servers for users
Service
DNS 1
DNS 2
Shecan	178.22.122.100	185.51.200.2
Electro	78.157.42.100	78.157.42.101
403.online	10.202.10.202	10.202.10.102
Begzar	185.55.226.26	185.55.225.25
Google	8.8.8.8	8.8.4.4
Cloudflare	1.1.1.1	1.0.0.1

System Architecture
text

┌─────────────────────────────────────────────────┐
│                     Client                       │
│         (Windows / Android / iOS / Linux)        │
└───────────────────┬─────────────────────────────┘
                    │ UDP 500/4500 (IPSec) + 1701 (L2TP)
┌───────────────────▼─────────────────────────────┐
│                  strongSwan                      │
│         (IKEv1 PSK, transport mode)             │
└───────────────────┬─────────────────────────────┘
┌───────────────────▼─────────────────────────────┐
│                   xl2tpd                         │
│            (L2TP daemon, port 1701)              │
└───────────────────┬─────────────────────────────┘
┌───────────────────▼─────────────────────────────┐
│                    pppd                          │
│   (CHAP auth via chap-secrets, per-user DNS     │
│    via iptables DNAT, traffic counters via      │
│    /sys/class/net)                               │
└───────────────────┬─────────────────────────────┘
┌───────────────────▼─────────────────────────────┐
│                iptables NAT                      │
│     (MASQUERADE to internet + DNS DNAT)         │
└───────────────────┴─────────────────────────────┘

┌─────────────────────────────────────────────────┐
│              Web Panel (gunicorn)                │
│           /opt/l2tp-panel/panel.py               │
│         (Flask + SQLite users.db)                │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│      sync_users.py (systemd timer, every 30s)    │
│   - sync users → chap-secrets                    │
│   - check expiry → disconnect sessions           │
│   - check quota → block + disconnect             │
│   - update DNS maps → iptables rules             │
│   - tally traffic from interface counters        │
└─────────────────────────────────────────────────┘
Files & paths
Path
Description
/opt/l2tp-panel/	Panel main directory
/opt/l2tp-panel/panel.py	Flask application
/opt/l2tp-panel/users.db	SQLite users database (back this up!)
/opt/l2tp-panel/config.json	Config (admin password, PSK, server IP)
/opt/l2tp-panel/templates/	HTML templates
/etc/ipsec.conf	strongSwan config
/etc/ipsec.secrets	PSK
/etc/ppp/chap-secrets	Active users (auto-managed — don't edit manually)
/etc/ppp/dns-map/	Per-user custom DNS files
/run/l2tp-sessions/	Online users' PIDs
/run/l2tp-ifaces/	Per-interface traffic counters

systemd services
bash

systemctl status l2tp-panel          # web panel
systemctl status strongswan-starter  # IPSec
systemctl status xl2tpd              # L2TP
systemctl status l2tp-nat            # NAT
systemctl list-timers | grep l2tp    # sync timer (every 30 seconds)
Backup
From the panel: Settings → Download backup — or via SSH:

bash

tar czf l2tp-backup-$(date +%F).tar.gz /opt/l2tp-panel/users.db /opt/l2tp-panel/config.json
🔧 Troubleshooting
Panel won't load
bash

systemctl status l2tp-panel
journalctl -u l2tp-panel -n 30 --no-pager
ss -tlnp | grep 8080    # or your chosen port
User can't connect
1. Watch live logs:

bash

journalctl -u strongswan-starter -u xl2tpd -f
2. What the errors mean:

Log message
Problem
Solution
Nothing appears	Datacenter firewall or ISP filtering	Open ports in datacenter panel; test with another carrier
NO_PROPOSAL_CHOSEN	Cipher mismatch	Open an issue
Authentication failed	Wrong username/password	Re-copy from panel
Connects but no internet	NAT problem	systemctl restart l2tp-nat
Error 809 on Windows	Blocked ports	Open UDP 500/4500

3. Check ports:

bash

ss -ulnp | grep -E ':(500|4500|1701)\b'
Connects but no internet
bash

systemctl is-active l2tp-nat
iptables -t nat -L POSTROUTING -n | grep MASQ   # should show MASQUERADE
ufw status | grep 43                            # should show route allow
Traffic usage not showing
bash

ls /run/l2tp-ifaces/                  # should contain pppX files
cat /run/l2tp-ifaces/ppp0             # should be "username bytes"
python3 /opt/l2tp-panel/sync_users.py # manual sync
Note: usage updates every ~30 seconds — give it a moment. Values under 1 GB are shown in MB.

Custom DNS not working
The user must disconnect and reconnect for new DNS rules to apply. Then from the client:

bash

nslookup google.com    # should resolve via the chosen DNS
Uninstall
bash

# Stop services
systemctl disable --now l2tp-panel l2tp-sync.timer l2tp-sync l2tp-nat strongswan-starter xl2tpd

# Remove system files
rm -f /etc/systemd/system/l2tp-{panel,nat,sync.service,sync.timer}
rm -rf /opt/l2tp-panel
rm -f /etc/ppp/ip-{up,down}.d/90l2tp-panel
rm -rf /etc/ppp/dns-map /run/l2tp-{sessions,ifaces,peerip}
rm -f /usr/local/sbin/l2tp-nat.sh

# Remove packages (optional)
apt-get remove -y strongswan* xl2tpd gunicorn python3-flask

systemctl daemon-reload
❓ FAQ
Are any passwords stored in the GitHub repo?
No — the admin password and PSK are randomly generated on each server during install and stored in that server's /opt/l2tp-panel/config.json.

What happens if I run the script again?
All configs get rewritten, but the users database (users.db) is preserved. Backups are also kept in /etc/*.bak-*.

How do I update the panel?
Press the Update Panel button inside the panel — it pulls the latest files from this repo's panel/ folder in ~15 seconds. No re-login needed.

How many concurrent users are supported?
Up to 240 concurrent users (pool 192.168.43.10–250).

Does it work on a server with other software installed?
Yes, but if you run a web server (nginx/apache) or an old strongSwan, port conflicts may occur.

📄 License
MIT License — free to use, modify and distribute.

🙏 Acknowledgements
strongSwan — IPSec daemon
xl2tpd — L2TP daemon
Flask — web framework
Vazirmatn — Persian font
<div align="center">

Built with ❤️ by 3OUTHBOY

⭐ If you found this useful, give it a star!

</div>
