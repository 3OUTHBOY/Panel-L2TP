```markdown
<div align="center">

# 🛡️ Panel-L2TP

**پنل مدیریت سرور VPN با پروتکل L2TP/IPSec — با نصب تک‌خطی**

L2TP/IPSec VPN server with a modern web management panel — one-line install

[![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04%20%7C%2022.04%20%7C%2024.04-E95420?style=flat-square&logo=ubuntu&logoColor=white)](https://ubuntu.com)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)
[![Panel](https://img.shields.io/badge/Web%20Panel-FA%20%2F%20EN-blueviolet?style=flat-square)](#-امکانات)
[![Installer](https://img.shields.io/badge/Install-One%20Line-00e5ff?style=flat-square)](#-نصب-سریع)

</div>

---

## 📖 فهرست
- [امکانات](#-امکانات)
- [نصب سریع](#-نصب-سریع)
- [راهنمای نصب](#-راهنمای-نصب)
- [اتصال کاربران](#-اتصال-کاربران)
- [مدیریت پنل](#-مدیریت-پنل)
- [معماری سیستم](#-معماری-سیستم)
- [عیب‌یابی](#-عیب‌یابی)
- [حذف کامل](#-حذف-کامل)

---

## ✨ امکانات

### 🔐 سرور VPN
| قابلیت | توضیحات |
|--------|---------|
| **L2TP/IPSec PSK** | سازگار با ویندوز، اندروید، iOS و مک — بدون نصب اپ جانبی |
| **strongSwan** | با پروپوزال‌های curve25519 و modp1024 برای سازگاری حداکثری (شامل iOS 17+) |
| **پول 192.168.43.x** | تا ۲۴۰ کاربر همزمان |
| **XAuth (اختیاری)** | کانفیگ Cisco IPsec برای کلاینت‌های قدیمی |
| **NAT + MSS Clamp** | اینترنت کامل با MTU بهینه |

### 👥 مدیریت کاربران
| قابلیت | توضیحات |
|--------|---------|
| **انقضای خودکار** | تاریخ و ساعت دقیق + قطع خودکار کاربر منقضی‌شده |
| **محدودیت حجم** | هر کاربر GB دلخواه + شمارش لحظه‌ای ترافیک (آپدیت هر ۳۰ ثانیه) |
| **DNS اختصاصی** | هر کاربر DNS خودش (شکن، الکترو، 403...) با ریدایرکت شفاف |
| **کد کاربر** | لینک وضعیت اختصاصی برای هر کاربر بدون لاگین |
| **قطع اتصال** | تغییر رمز یا حذف کاربر = قطع فوری اتصال |

### 🖥️ پنل وب
| قابلیت | توضیحات |
|--------|---------|
| **دوزبانه** | فارسی (RTL) / انگلیسی (LTR) با یک کلیک |
| **تم تاریک/روشن** | تم سایبرپانک نئونی + تم لایت مینیمال |
| **گوی موس** | افکت glow cursor با رنگ هماهنگ تم |
| **داشبورد** | وضعیت سرویس‌ها، کاربران آنلاین، آمار کلی |
| **ریستارت** | دکمه ریستارت VPN و پنل از داخل خود پنل |

---

## 🚀 نصب سریع

### روش تعاملی (پیشنهادی)

روی سرور اوبونتو خود به عنوان root یا با sudo:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/3OUTHBOY/Panel-L2TP/main/install.sh)
```

نصب‌کننده چند سؤال می‌پرسد:
- نام کاربری و رمز عبور ادمین پنل
- **پورت پنل** (دلخواه، پیش‌فرض 8080)
- کلید PSK (پیش‌فرض: تولید خودکار امن)
- IP مجاز برای دسترسی به پنل (اختیاری)
- منطقه زمانی و فایروال

پس از ~۲ دقیقه، اطلاعات اتصال نمایش داده می‌شود:

```
=====================================================
     Panel-L2TP — Installation complete!
=====================================================
 Panel URL       : http://YOUR_SERVER_IP:8080
 Admin username  : admin
 Admin password  : xK9mP2nQ8rT4
 IPSec PSK       : aB3cD4eF5gH6iJ7kL8mN
=====================================================
```

### روش غیرتعاملی (برای automation و cloud-init)

```bash
bash <(curl -Ls https://raw.githubusercontent.com/3OUTHBOY/Panel-L2TP/main/install.sh) \
  --user admin \
  --pass MyStrongPass123 \
  --port 9443 \
  --psk MySecretPSK \
  --no-ufw
```

| فلگ | پیش‌فرض | توضیح |
|-----|---------|-------|
| `--user` | `admin` | نام کاربری ادمین |
| `--pass` | رندوم | رمز عبور ادمین |
| `--port` | `8080` | پورت پنل (انتخاب خودکار کاربر) |
| `--psk` | رندوم | کلید IPSec |
| `--admin-ip` | خالی | IP مجاز برای پنل (خالی = بدون محدودیت) |
| `--no-ufw` | فعال | فایروال UFW نصب نشود |

> 💡 از `bash <(curl ...)` استفاده شده نه `curl | bash` تا سوالات تعاملی (رمز/پورت/PSK) درست کار کنند.

---

## 📱 اتصال کاربران

### ویندوز
1. **Settings → Network & Internet → VPN → Add a VPN connection**
2. VPN provider: `Windows (built-in)`
3. Connection name: هر چه دوست دارید
4. Server name or address: IP سرور
5. VPN type: **`L2TP/IPsec with pre-shared key`**
6. Pre-shared key: از پنل کپی کنید
7. Type of sign-in info: **Username and password**
8. Username / Password: از پنل

> اگر خطای **809** گرفتید: پورت‌های UDP 500 و 4500 را در فایروال ویندوز و مودم/روتر باز کنید.

### اندروید
1. **Settings → Network & Internet → VPN → +**
2. Name: دلخواه
3. Type: **`L2TP/IPSec PSK`**
4. Server address: IP سرور
5. IPSec pre-shared key: از پنل
6. Username / Password: از پنل

### iOS / macOS
1. **Settings → VPN → Add VPN Configuration**
2. Type: **`L2TP`**
3. Description: دلخواه
4. Server: IP سرور
5. Account: نام کاربری
6. Password: رمز عبور
7. Secret: از پنل

> iOS 17+ به‌صورت خودکار با پروپوزال‌های curve25519/modp1024 چانه‌زنی می‌کند — نیازی به تنظیم خاص نیست.

### لینوکس (NetworkManager)
```bash
nmcli connection add type vpn vpn-type l2tp \
  con-name "MyVPN" vpn.data "gateway=SERVER_IP, ipsec-enabled=yes, ipsec-psk=YOUR_PSK" \
  vpn.secrets "username=USER, password=PASS"
```

---

## 🎛️ مدیریت پنل

### داشبورد

بعد از ورود، این بخش‌ها را می‌بینید:

- **کارت‌های آمار**: آدرس سرور، PSK (با دکمه نمایش/کپی)، کاربران فعال، نشست‌های متصل
- **وضعیت سرویس‌ها**: IPSec / L2TP / NAT — سبز = فعال، قرمز = مشکل
- **افزودن کاربر**: نام کاربری، رمز (خالی = تولید خودکار)، مدت اعتبار (روز)، محدودیت حجم (GB)، DNS اول/دوم، تاریخ دقیق انقضا
- **جدول کاربران**: رمز (مخفی/نمایش)، انقضا، باقی‌مانده، حجم مصرفی (با نوار پیشرفت رنگی)، DNS اختصاصی، کد کاربر، وضعیت، عملیات

### عملیات هر کاربر

| دکمه | عملکرد |
|------|--------|
| **تمدید + عدد روز** | اضافه کردن روز به انقضای کاربر |
| **✏️ ویرایش** | رمز، تاریخ انقضا، حجم، DNS، کد کاربر |
| **♻️ ریست حجم** | صفر کردن شمارنده مصرف |
| **🔑 کد جدید** | تولید کد رندوم جدید (لینک قبلی باطل می‌شود) |
| **🗑 حذف** | حذف کامل کاربر + قطع فوری اتصال |

### 🔗 لینک وضعیت کاربر

هر کاربر یک کد یکتا دارد. این لینک را به او بدهید:

```
http://SERVER_IP:PORT/u/USER_KEY
```

کاربر بدون لاگین می‌تواند ببیند:
- اطلاعات اتصال کامل (سرور، PSK، یوزر/پسورد، DNS اختصاصی)
- زمان باقی‌مانده و حجم مصرفی با نوار پیشرفت
- وضعیت فعال / منقضی / اتمام حجم

> ⚠️ این لینک شامل رمز عبور VPN است — فقط به خود کاربر بدهید!

### دکمه‌های ریستارت

- **🚀 Restart VPN**: ریستارت strongSwan + xl2tpd + NAT (کاربران متصل موقتاً قطع می‌شوند و معمولاً خودکار وصل می‌شوند)
- **♻️ Restart Panel**: ریستارت پنل وب با بازگشت خودکار بعد از چند ثانیه

### تغییر زبان و تم

- **EN / FA** گوشه پایین صفحه: تغییر زبان (فارسی ⇄ انگلیسی)
- **☀️ / 🌙**: تغییر تم (تاریک ⇄ روشن) — انتخاب شما در مرورگر ذخیره می‌شود

### DNS های پیشنهادی برای کاربران

| سرویس | DNS ۱ | DNS ۲ |
|--------|-------|-------|
| شکن | 178.22.122.100 | 185.51.200.2 |
| الکترو | 78.157.42.100 | 78.157.42.101 |
| 403.online | 10.202.10.202 | 10.202.10.102 |
| بگذر | 185.55.226.26 | 185.55.225.25 |
| گوگل | 8.8.8.8 | 8.8.4.4 |
| کلادفلر | 1.1.1.1 | 1.0.0.1 |

---

## 🏗️ معماری سیستم

```
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
```

### فایل‌ها و مسیرها

| مسیر | توضیح |
|------|-------|
| `/opt/l2tp-panel/` | دایرکتوری اصلی پنل |
| `/opt/l2tp-panel/panel.py` | اپلیکیشن Flask |
| `/opt/l2tp-panel/users.db` | دیتابیس SQLite کاربران (**بکاپ بگیرید!**) |
| `/opt/l2tp-panel/config.json` | تنظیمات (رمز ادمین، PSK، IP سرور) |
| `/opt/l2tp-panel/templates/` | قالب‌های HTML |
| `/etc/ipsec.conf` | کانفیگ strongSwan |
| `/etc/ipsec.secrets` | PSK |
| `/etc/ppp/chap-secrets` | کاربران فعال (مدیریت خودکار — دستی ویرایش نکنید) |
| `/etc/ppp/dns-map/` | فایل DNS اختصاصی هر کاربر |
| `/run/l2tp-sessions/` | PID کاربران آنلاین |
| `/run/l2tp-ifaces/` | شمارنده ترافیک هر اینترفیس |

### سرویس‌های systemd

```bash
systemctl status l2tp-panel          # پنل وب
systemctl status strongswan-starter  # IPSec
systemctl status xl2tpd              # L2TP
systemctl status l2tp-nat            # NAT
systemctl list-timers | grep l2tp    # تایمر همگام‌سازی (هر ۳۰ ثانیه)
```

### بکاپ‌گیری

```bash
# بکاپ کامل کاربران و تنظیمات
tar czf l2tp-backup-$(date +%F).tar.gz /opt/l2tp-panel/users.db /opt/l2tp-panel/config.json

# بازگردانی
tar xzf l2tp-backup-DATE.tar.gz -C /
systemctl restart l2tp-panel
python3 /opt/l2tp-panel/sync_users.py
```

---

## 🔧 عیب‌یابی

### پنل بالا نمی‌آید

```bash
systemctl status l2tp-panel
journalctl -u l2tp-panel -n 30 --no-pager
ss -tlnp | grep 8080    # یا پورت انتخابی شما
```

### کاربر وصل نمی‌شود

**۱. لاگ زنده را ببینید:**

```bash
journalctl -u strongswan-starter -u xl2tpd -f
```

**۲. معنی خطاها:**

| پیام لاگ | مشکل | راه‌حل |
|----------|------|-------|
| هیچ پیامی نمی‌آید | فایروال دیتاسنتر یا فیلترینگ ISP | پورت‌ها را در پنل دیتاسنتر باز کنید؛ با اپراتور دیگه تست کنید |
| `NO_PROPOSAL_CHOSEN` | عدم تطابق cipher | با issue بپرسید |
| `Authentication failed` | یوزر/پسورد غلط | از پنل دوباره کپی کنید |
| وصل می‌شود اما اینترنت نیست | مشکل NAT | `systemctl restart l2tp-nat` |
| خطای 809 در ویندوز | پورت بسته | UDP 500/4500 را باز کنید |

**۳. وضعیت پورت‌ها:**

```bash
ss -ulnp | grep -E ':(500|4500|1701)\b'
```

### وصل می‌شود اما اینترنت نیست

```bash
systemctl is-active l2tp-nat
iptables -t nat -L POSTROUTING -n | grep MASQ   # باید MASQUERADE ببینید
ufw status | grep 43                            # باید route allow باشد
```

### مصرف حجم نمایش داده نمی‌شود

```bash
ls /run/l2tp-ifaces/                  # باید فایل pppX باشد
cat /run/l2tp-ifaces/ppp0             # باید «username bytes» باشد
python3 /opt/l2tp-panel/sync_users.py # اجرای دستی sync
```

> نکته: مصرف هر ~۳۰ ثانیه آپدیت می‌شود — کمی صبر کنید. مقدار زیر ۱ گیگ به MB نمایش داده می‌شود.

### DNS اختصاصی کار نمی‌کند

کاربر باید **قطع و وصل** شود تا قوانین جدید DNS اعمال شود. سپس از کلاینت:

```bash
nslookup google.com    # باید از DNS انتخابی پاسخ بگیرد
```

---

## 🗑️ حذف کامل

```bash
# توقف سرویس‌ها
systemctl disable --now l2tp-panel l2tp-sync.timer l2tp-sync l2tp-nat strongswan-starter xl2tpd

# حذف فایل‌های سیستم
rm -f /etc/systemd/system/l2tp-{panel,nat,sync.service,sync.timer}
rm -rf /opt/l2tp-panel
rm -f /etc/ppp/ip-{up,down}.d/90l2tp-panel
rm -rf /etc/ppp/dns-map /run/l2tp-{sessions,ifaces,peerip}
rm -f /usr/local/sbin/l2tp-nat.sh

# حذف پکیج‌ها (اختیاری)
apt-get remove -y strongswan* xl2tpd gunicorn python3-flask

systemctl daemon-reload
```

---

## ❓ سوالات متداول

**آیا رمزها داخل مخزن گیت‌هاب هستند؟**
خیر — رمز ادمین و PSK موقع نصب روی هر سرور به‌صورت رندوم تولید می‌شوند و در `/opt/l2tp-panel/config.json` همان سرور ذخیره می‌شوند.

**اگر اسکریپت را دوباره اجرا کنم چه می‌شود؟**
همه‌ی کانفیگ‌ها بازنویسی می‌شوند اما دیتابیس کاربران (`users.db`) حفظ می‌شود. از بکاپ‌ها در `/etc/*.bak-*` هم نگه داشته می‌شود.

**چند کاربر همزمان ساپورت می‌شود؟**
تا ۲۴۰ کاربر همزمان (پول 192.168.43.10 تا 250).

**روی سروری که چیز دیگری نصب است کار می‌کند؟**
بله، ولی اگر وب‌سرور (nginx/apache) یا strongSwan قدیمی دارید، ممکن است تداخل پورت پیش بیاید.

---

## 📄 لایسنس

MIT License — استفاده، تغییر و توزیع آزاد است.

---

## 🙏 تشکر از

- [strongSwan](https://www.strongswan.org/) — IPSec daemon
- [xl2tpd](https://github.com/xelerance/xl2tpd) — L2TP daemon
- [Flask](https://flask.palletsprojects.com/) — web framework
- [Vazirmatn](https://github.com/rastikerdar/vazirmatn) — فونت فارسی
- [Uiverse](https://uiverse.io/) — الهام طراحی UI

---

<div align="center">

**ساخته شده با ❤️ توسط [3OUTHBOY](https://github.com/3OUTHBOY)**

⭐ اگر مفید بود، ستاره بدهید!

</div>
