(() => {
'use strict';
const cfg=window.CSP_CM_CONFIG;
if(!cfg||!window.supabase) throw new Error('Supabase configuration is missing.');
const db=window.supabase.createClient(cfg.supabaseUrl,cfg.supabaseAnonKey);
const parts=location.pathname.split('/').filter(Boolean);
const routeNames=new Set(['login','dashboard','venues','reservations','reports','dochadzka','personal','bar']);
if(parts.length&&routeNames.has(parts.at(-1)))parts.pop();
const rootPath='/'+(parts.length?parts.join('/')+'/':'');
const route=(name='')=>rootPath+String(name).replace(/^\/+/,'');
const esc=v=>String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));

const CM_LANGUAGES={sk:'SK',cs:'CZ',en:'EN',de:'DE',pl:'PL'};
const CM_LANG_KEY='csp_cm_language';
function currentLanguage(){
  const saved=localStorage.getItem(CM_LANG_KEY);
  if(saved&&CM_LANGUAGES[saved])return saved;
  const cookie=document.cookie.match(/(?:^|;\s*)googtrans=\/sk\/([^;]+)/);
  return cookie&&CM_LANGUAGES[cookie[1]]?cookie[1]:'sk';
}
function setTranslateCookie(lang){
  const value=lang==='sk'?'':`/sk/${lang}`;
  const expires=lang==='sk'?'; expires=Thu, 01 Jan 1970 00:00:00 GMT':'; max-age=31536000';
  document.cookie=`googtrans=${value}; path=/${expires}; SameSite=Lax`;
  document.cookie=`googtrans=${value}; path=/; domain=.${location.hostname}${expires}; SameSite=Lax`;
}
function changeLanguage(lang){
  if(!CM_LANGUAGES[lang])lang='sk';
  localStorage.setItem(CM_LANG_KEY,lang);
  setTranslateCookie(lang);
  location.reload();
}
function googleTranslateElementInit(){
  if(!window.google?.translate?.TranslateElement)return;
  new google.translate.TranslateElement({
    pageLanguage:'sk',
    includedLanguages:'cs,en,de,pl,sk',
    autoDisplay:false
  },'google_translate_element');
}
window.googleTranslateElementInit=googleTranslateElementInit;
function injectLanguageControl(){
  if(document.getElementById('cspLanguageSelect'))return;
  const style=document.createElement('style');
  style.textContent=`
    .csp-lang-wrap{display:inline-flex;align-items:center;gap:7px;margin-left:auto}
    .csp-lang-wrap::before{content:'🌐';font-size:15px}
    .csp-lang-select{min-height:38px;padding:0 30px 0 10px;border:1px solid rgba(255,255,255,.12);border-radius:9px;background:#171717;color:#fff;font-weight:800;cursor:pointer}
    #google_translate_element,.goog-te-banner-frame,.skiptranslate iframe{display:none!important}
    body{top:0!important}
    .goog-logo-link,.goog-te-gadget{display:none!important}
    .notranslate{translate:no}
    @media(max-width:760px){.csp-lang-wrap{margin-left:0}.csp-lang-select{min-height:36px}}
  `;
  document.head.appendChild(style);
  const wrap=document.createElement('div');
  wrap.className='csp-lang-wrap notranslate';
  wrap.setAttribute('translate','no');
  wrap.innerHTML=`<select id="cspLanguageSelect" class="csp-lang-select" aria-label="Jazyk">${Object.entries(CM_LANGUAGES).map(([code,label])=>`<option value="${code}">${label}</option>`).join('')}</select><div id="google_translate_element" aria-hidden="true"></div>`;
  const topbar=document.querySelector('.topbar');
  const logout=topbar?.querySelector('#logout');
  if(topbar){
    if(logout)topbar.insertBefore(wrap,logout);else topbar.appendChild(wrap);
  }else{
    wrap.style.cssText='position:fixed;top:16px;right:16px;z-index:5000';
    document.body.appendChild(wrap);
  }
  const select=document.getElementById('cspLanguageSelect');
  select.value=currentLanguage();
  select.addEventListener('change',()=>changeLanguage(select.value));
  document.querySelectorAll('.brand,.brand-name,.brand-sub,#clubName').forEach(el=>{el.classList.add('notranslate');el.setAttribute('translate','no')});
  const script=document.createElement('script');
  script.src='https://translate.google.com/translate_a/element.js?cb=googleTranslateElementInit';
  script.async=true;
  script.dataset.cspGoogleTranslate='1';
  document.head.appendChild(script);
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',injectLanguageControl,{once:true});
else injectLanguageControl();

const api={
 db,route,esc,
 async session(){const {data,error}=await db.auth.getSession();if(error)throw error;return data.session;},
 async requireAccess(){
   const incomingClub=new URLSearchParams(location.search).get('club');
   if(incomingClub)localStorage.setItem('csp_cm_expected_club',incomingClub);
   const expectedClub=localStorage.getItem('csp_cm_expected_club');

   const session=await api.session();
   if(!session){
     const ret=location.pathname+location.search;
     location.replace(route('login/?returnTo=')+encodeURIComponent(ret));
     throw new Error('LOGIN_REQUIRED');
   }

   const {data,error}=await db.rpc('club_manager_bootstrap');if(error)throw error;
   if(!data?.allowed){
     document.body.innerHTML=`<main class="access-denied"><section><div class="brand-mark">C</div><h1>Club Manager nemáte aktivovaný</h1><p>Prístup určuje oprávnenie účtu. Technické označenia Ultra, Elite a Admin nie sú súčasťou používateľského obsahu.</p><a href="https://connectsportspro.com/">Späť na CONNECT SPORTS PRO</a><button id="logoutDenied">Odhlásiť sa</button></section></main>`;
     document.getElementById('logoutDenied').onclick=async()=>{await db.auth.signOut();localStorage.removeItem('csp_cm_expected_club');location.replace(route('login/'));};
     throw new Error('PLAN_REQUIRED');
   }

   if(expectedClub && data?.club?.id && data.club.id!==expectedClub){
     const ret=location.pathname+location.search;
     await db.auth.signOut();
     document.body.innerHTML=`<main class="access-denied"><section><div class="brand-mark">C</div><h1>Prihlásený je iný klubový účet</h1><p>Club Manager bol otvorený pre iný klub. Prihlás sa účtom, ktorý patrí k profilu, z ktorého si Club Manager otvoril.</p><a href="${route('login/?returnTo=')+encodeURIComponent(ret)}">Prihlásiť správny účet</a></section></main>`;
     throw new Error('CLUB_CONTEXT_MISMATCH');
   }

   if(expectedClub && !data?.club?.id){
     throw new Error('CLUB_CONTEXT_NOT_FOUND');
   }

   return data;
 },
 money:v=>`${Number(v||0).toFixed(2)} €`,
 time(seconds){seconds=Math.max(0,Math.floor(Number(seconds||0)));const h=Math.floor(seconds/3600),m=Math.floor((seconds%3600)/60),s=seconds%60;return h?`${String(h).padStart(2,'0')}:${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}`:`${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}`;},
 currentSeconds(s){const base=Number(s.accumulated_seconds||0);return s.status==='running'&&s.started_at?base+Math.max(0,Math.floor((Date.now()-new Date(s.started_at).getTime())/1000)):base;},
 scoreboardSport(st){const v=String(st?.sport||'').toLowerCase();return v.includes('dart')||v.includes('šíp')?'darts':v.includes('billiard')||v.includes('biliard')||v.includes('pool')?'billiard':'other';},
 scoreboardUrl(st){const u=new URL('https://connectsportspro.com/scoreboard/');u.searchParams.set('station',st.name);u.searchParams.set('station_id',st.id);u.searchParams.set('sport',api.scoreboardSport(st));u.searchParams.set('lock',st.lock_mode?'1':'0');if(st.token)u.searchParams.set('station_token',st.token);u.searchParams.set('from',location.origin+route('dashboard/'));return u.toString();},
 subscribe(clubId,handler){return db.channel(`cm-${clubId}`).on('postgres_changes',{event:'*',schema:'public',table:'club_manager_live_sessions',filter:`club_id=eq.${clubId}`},handler).on('postgres_changes',{event:'*',schema:'public',table:'stations',filter:`club_id=eq.${clubId}`},handler).on('postgres_changes',{event:'*',schema:'public',table:'reservations',filter:`club_id=eq.${clubId}`},handler).subscribe();},
 async logout(){await db.auth.signOut();location.replace(route('login/'));}
};
const setNetwork=()=>document.documentElement.classList.toggle('offline',!navigator.onLine);
addEventListener('online',setNetwork);addEventListener('offline',setNetwork);setNetwork();
if('serviceWorker'in navigator)navigator.serviceWorker.register(route('service-worker.js')).catch(()=>{});
window.CSPClubManager=api;
})();