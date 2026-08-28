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
PANEL_VERSION = '2.0.0'
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
  'logout_btn':'خروج','copy_tip':'کپی','show_tip':'نمایش',
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
        if d > 0: return '{} روز و {} ساعت'.format(d, h)
        if h > 0: return '{} ساعت و {} دقیقه'.format(h, m)
        return '{} دقیقه'.format(max(m, 1))
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
               if limit_mb > 0 else '{} / ∞'.format(fmt_traffic(used)))
    remaining = fmt_remaining(secs, lang) if not expired and not quota_exceeded else '—'
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
