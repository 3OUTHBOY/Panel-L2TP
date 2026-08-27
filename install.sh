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
html[dir=ltr] body{font-family:system-ui,-apple-system,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif}html[dir=ltr] .gheading,html[dir=ltr] .login-heading{letter-spacing:3px}
.container{max-width:1180px;margin:0 auto;padding:0 16px}
header{background:var(--panel-bg);backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);
  border-bottom:1px solid var(--border-neon);padding:15px 0;margin-bottom:24px;
  position:sticky;top:0;z-index:40;box-shadow:0 10px 30px rgba(0,0,0,.35)}
[data-theme=light] header{box-shadow:var(--sh2)}
.header-in{display:flex;justify-content:space-between;align-items:center;gap:10px;flex-wrap:wrap}
.brand{display:flex;align-items:center;gap:12px}
.brand-badge{width:42px;height:42px;border-radius:13px;display:grid;place-items:center;font-size:1.25rem;
  background:linear-gradient(45deg,var(--neon-cyan),var(--neon-purple));
  box-shadow:0 0 15px rgba(0,229,255,.3);flex:none}
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
.svc-row{display:flex;gap:8px;flex-wrap:wrap}
.svc{padding:5px 13px;border-radius:9px;font-size:.76rem;font-weight:700}
.svc.ok{background:rgba(52,211,153,.13);color:var(--grn)}
.svc.bad{background:rgba(248,113,113,.13);color:var(--red)}
[data-theme=light] .svc.ok{background:#dcfce7;color:#15803d}
[data-theme=light] .svc.bad{background:#fee2e2;color:#b91c1c}
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
@media(max-width:600px){h1{font-size:.95rem}.card{padding:16px}}
/* Aura cursor: hide ALL native cursors + glow follower */
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
/* ===== logo-update: L2TP tunnel shield ===== */
.lg-a{stop-color:var(--neon-cyan)}
.lg-b{stop-color:var(--neon-purple)}
.logo-svg{display:block;filter:drop-shadow(0 0 6px color-mix(in srgb,var(--neon-cyan) 45%,transparent))}
[data-theme=light] .logo-svg{filter:drop-shadow(0 0 5px color-mix(in srgb,var(--acc) 30%,transparent))}
.logo-svg circle{animation:lgpulse 2.6s ease-in-out infinite}
@keyframes lgpulse{0%,100%{opacity:1}50%{opacity:.4}}
.brand-badge{width:46px;height:46px;border-radius:14px;font-size:0;
  background:var(--card3);border:1px solid var(--bd2);box-shadow:0 0 16px rgba(0,229,255,.18)}
.brand-badge .logo-svg{width:31px;height:31px}
.login-logo{width:66px;height:66px;border-radius:19px;display:grid;place-items:center;margin:0 auto 12px;
  background:var(--card3);border:1px solid var(--bd2);box-shadow:0 0 20px rgba(0,229,255,.22)}
.login-logo .logo-svg{width:44px;height:44px}
.restart-logo{width:66px;height:66px;border-radius:19px;display:grid;place-items:center;margin:0 auto 12px;  background:var(--card3);border:1px solid var(--bd2);box-shadow:0 0 20px rgba(0,229,255,.22)}
.restart-logo .logo-svg{width:44px;height:44px}
</style>
</head>
<body>
<div class="ctrl-cluster">
  <button type="button" class="ctrl-btn" id="themeBtn" onclick="toggleTheme()" title="{{ t.theme_tip }}">🌙</button>
  <a class="ctrl-btn" href="/lang/{{ 'en' if lang == 'fa' else 'fa' }}" title="{{ lang|upper }}">{{ 'EN' if lang == 'fa' else 'FA' }}</a>
</div>
{% block body %}{% endblock %}
<script>
function applyThemeBtn(){
  var cur=document.documentElement.getAttribute('data-theme')||'dark';
  var b=document.getElementById('themeBtn');
  if(b){b.textContent = cur==='dark' ? '☀️' : '🌙';}
}
function toggleTheme(){
  var cur=document.documentElement.getAttribute('data-theme')||'dark';
  var next=cur==='dark'?'light':'dark';
  document.documentElement.setAttribute('data-theme',next);
  try{localStorage.setItem('l2tp-theme',next);}catch(e){}
  applyThemeBtn();
}
applyThemeBtn();
function copyText(t,b){var d=function(){var o=b.innerHTML;b.innerHTML='✓';setTimeout(function(){b.innerHTML=o;},1200);};if(navigator.clipboard&&window.isSecureContext){navigator.clipboard.writeText(t).then(d);}else{var a=document.createElement('textarea');a.value=t;a.style.position='fixed';a.style.opacity='0';document.body.appendChild(a);a.select();document.execCommand('copy');a.remove();d();}}
document.querySelectorAll('.copy-btn').forEach(function(b){b.addEventListener('click',function(){copyText(b.getAttribute('data-copy'),b);});});
document.querySelectorAll('.reveal').forEach(function(b){b.addEventListener('click',function(){var s=b.parentElement.querySelector('.pw');if(s.getAttribute('data-shown')==='1'){s.textContent='••••••••';s.setAttribute('data-shown','0');b.textContent='👁';}else{s.textContent=s.getAttribute('data-pw');s.setAttribute('data-shown','1');b.textContent='🙈';}});});
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
  document.addEventListener('pointerout',function(e){if(e.target.closest(sel))o.classList.remove('hot');});  document.addEventListener('pointerdown',function(){o.classList.add('click');});
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
      <div class="login-logo"><svg class="logo-svg" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg"
role="img" aria-label="L2TP"><defs><linearGradient id="lgl" x1="10" y1="6" x2="54" y2="58" gradientUnits="userSpaceOnUse"><stop class="lg-a" offset="0"/><stop class="lg-b" offset="1"/></linearGradient></defs><path
d="M32 4 L55.5 12.5 V28 C55.5 42.5 46 52.5 32 59.5 C18 52.5 8.5 42.5 8.5 28 V12.5 Z" stroke="url(#lgl)" stroke-width="3.4" stroke-linejoin="round" fill="url(#lgl)" fill-opacity="0.08"/><path d="M22 46.5 V29 C22 21.8 26.4 16 32 16 C37.6 16 42 21.8 42 29 V46.5" stroke="url(#lgl)" stroke-width="2.6" stroke-linecap="round"/><path d="M28 46.5 V31.5 C28 27 29.7 23.5 32 23.5 C34.3 23.5 36 27 36 31.5 V46.5" stroke="url(#lgl)" stroke-width="2" stroke-linecap="round" opacity="0.6"/><circle cx="32" cy="36.5" r="3" fill="url(#lgl)"/></svg></div>
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
      <div class="stat-head"><span class="stat-icon">🌐</span><span class="stat-label">{{ t.server_address
}}</span></div>
      <div class="secret-row"><b class="pw">{{ server_ip }}</b>
        <button type="button" class="icon-btn copy-btn" data-copy="{{ server_ip }}" title="{{ t.copy_tip }}">📋</button></div>
    </div>
    <div class="card stat">
      <div class="stat-head"><span class="stat-icon">🔑</span><span class="stat-label">{{ t.psk_label }}</span></div>
      <div class="secret-row">
        <span class="pw" data-pw="{{ psk }}" data-shown="0">••••••••</span>
        <button type="button" class="icon-btn reveal" title="{{ t.show_tip }}">👁</button>
        <button type="button" class="icon-btn copy-btn" data-copy="{{ psk }}" title="{{ t.copy_tip }}">📋</button>
      </div>
    </div>
    <div class="card stat">
      <div class="stat-head"><span class="stat-icon">👤</span><span class="stat-label">{{ t.active_users }}</span></div>
      <b>{{ active_count }} {{ t.of_word }} {{ total_count }}</b>
    </div>
    <div class="card stat">
      <div class="stat-head"><span class="stat-icon">📡</span><span class="stat-label">{{ t.online_sessions }}</span></div>
      <b>{{ online_count }}</b>
    </div>
    <div class="card stat">
      <div class="stat-head"><span class="stat-icon">⚙️</span><span class="stat-label">{{ t.services_status }}</span></div>
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
          <button type="button" class="btn small" onclick="genPass()">🎲</button>
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
        <button class="btn primary">＋  {{ t.add_btn }}</button>
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
            <th>{{ t.th_remaining }}</th><th>{{ t.th_traffic }}</th><th>{{ t.th_dns }}</th><th>{{ t.th_key
}}</th>
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
                <span class="pw" data-pw="{{ u.password }}" data-shown="0">••••••••</span>
                <button type="button" class="icon-btn reveal" title="{{ t.show_tip }}">👁</button>
                <button type="button" class="icon-btn copy-btn" data-copy="{{ u.password }}" title="{{ t.copy_tip }}">📋</button>
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
                <span class="pw">{{ u.dns1 or '—' }} / {{ u.dns2 or '—' }}</span>
              {% else %}
                <span class="muted">{{ t.default_dns }}</span>
              {% endif %}
            </td>
            <td>
              <span class="secret-row">
                <span class="pw">{{ u.key }}</span>
                <button type="button" class="icon-btn copy-btn" data-copy="{{ u.key }}" title="{{ t.copy_tip }}">📋</button>
                <a class="icon-btn" href="/u/{{ u.key }}" target="_blank" title="{{ t.status_link_tip }}">🔗</a>
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
              <button class="btn small" onclick="openEdit({{ u.id }}, '{{ u.expires_input }}', '{{ u.dns1 }}', '{{ u.dns2 }}', '{{ u.key }}')">✏️</button>
              <form method="post" action="/reset-traffic/{{ u.id }}" class="inline">
                <button class="btn small" title="{{ t.reset_traffic_tip }}">♻️</button>
              </form>
              <form method="post" action="/regen-key/{{ u.id }}" class="inline">
                <button class="btn small" title="{{ t.regen_key_tip }}">🔑</button>
              </form>
              <form method="post" action="/delete/{{ u.id }}" class="inline" onsubmit="return confirm('{{ t.delete_confirm }}')">
                <button class="btn small danger">🗑</button>
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
    <h3>✏️ {{ t.edit_title }}</h3>
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
        <span class="sb-sub">{{ u.username }} · L2TP/IPSec</span>
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
            <b>∞</b>
          {% endif %}
          <span>{{ u.traffic }}</span>
        </div>
      </div>
      <div class="gauge-side">
        <div class="mini-stat">
          <div class="ms-label">⏱ {{ t.st_remaining }}</div>
          {% if u.expired or u.quota_exceeded %}
            <div class="ms-value muted">—</div>
          {% else %}
            <div class="countdown" id="liveCountdown" data-expires="{{ u.expires }}">
              <div class="cd-box"><b id="cdD">—</b><span>{{ 'روز' if lang=='fa' else 'D' }}</span></div>
              <div class="cd-box"><b id="cdH">—</b><span>{{ 'ساعت' if lang=='fa' else 'H' }}</span></div>
              <div class="cd-box"><b id="cdM">—</b><span>{{ 'دقیقه' if lang=='fa' else 'M' }}</span></div>
              <div class="cd-box"><b id="cdS">—</b><span>{{ 'ثانیه' if lang=='fa' else 'S' }}</span></div>
            </div>
          {% endif %}
        </div>
        <div class="mini-stat">
          <div class="ms-label">📅 {{ t.st_expiry }}</div>
          <div class="ms-value pw">{{ u.expires }}</div>
        </div>
      </div>
    </div>
    <div class="sub-divider"><span>{{ t.st_type }}</span></div>
    <div class="sub-info">
      <div class="info-row"><span>{{ t.st_server }}</span>
        <div class="secret-row"><b class="pw">{{ server_ip }}</b>
          <button type="button" class="icon-btn copy-btn" data-copy="{{ server_ip }}" title="{{ t.copy_tip
}}">📋</button></div>
      </div>
      <div class="info-row"><span>{{ t.st_psk }}</span>
        <div class="secret-row">
          <span class="pw" data-pw="{{ psk }}" data-shown="0">••••••••</span>
          <button type="button" class="icon-btn reveal" title="{{ t.show_tip }}">👁</button>
          <button type="button" class="icon-btn copy-btn" data-copy="{{ psk }}" title="{{ t.copy_tip }}">📋</button>
        </div>
      </div>
      <div class="info-row"><span>{{ t.username }}</span>
        <div class="secret-row"><b class="pw">{{ u.username }}</b>
          <button type="button" class="icon-btn copy-btn" data-copy="{{ u.username }}" title="{{ t.copy_tip }}">📋</button></div>
      </div>
      <div class="info-row"><span>{{ t.password }}</span>
        <div class="secret-row">
          <span class="pw" data-pw="{{ u.password }}" data-shown="0">••••••••</span>
          <button type="button" class="icon-btn reveal" title="{{ t.show_tip }}">👁</button>
          <button type="button" class="icon-btn copy-btn" data-copy="{{ u.password }}" title="{{ t.copy_tip }}">📋</button>
        </div>
      </div>
      <div class="info-row"><span>{{ t.st_dns }}</span>
        <b class="pw">{% if u.dns1 or u.dns2 %}{{ u.dns1 or '—' }} / {{ u.dns2 or '—' }}{% else %}{{ t.st_dns_default }}{% endif %}</b>
      </div>
    </div>
    <div class="sub-footer">
      <span class="muted">{{ t.brand }} · v{{ panel_version }}</span>
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
    <div class="restart-logo"><svg class="logo-svg" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg"
role="img" aria-label="L2TP"><defs><linearGradient id="lgr" x1="10" y1="6" x2="54" y2="58" gradientUnits="userSpaceOnUse"><stop class="lg-a" offset="0"/><stop class="lg-b" offset="1"/></linearGradient></defs><path
d="M32 4 L55.5 12.5 V28 C55.5 42.5 46 52.5 32 59.5 C18 52.5 8.5 42.5 8.5 28 V12.5 Z" stroke="url(#lgr)" stroke-width="3.4" stroke-linejoin="round" fill="url(#lgr)" fill-opacity="0.08"/><path d="M22 46.5 V29 C22 21.8 26.4 16 32 16 C37.6 16 42 21.8 42 29 V46.5" stroke="url(#lgr)" stroke-width="2.6" stroke-linecap="round"/><path d="M28 46.5 V31.5 C28 27 29.7 23.5 32 23.5 C34.3 23.5 36 27 36 31.5 V46.5" stroke="url(#lgr)" stroke-width="2" stroke-linecap="round" opacity="0.6"/><circle cx="32" cy="36.5" r="3" fill="url(#lgr)"/></svg></div>
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
.upd-bar{height:6px;background:rgba(255,255,255,.07);border-radius:99px;overflow:hidden;margin:18px 0 14px}[data-theme=light] .upd-bar{background:#e2e8f4}
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
echo -e "${GREEN}      3OUTHBOY PANEL — Installation complete!        ${NC}"
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
