(() => {
'use strict';

const auth=window.cspAuth;
if(!auth) return;

const $=id=>document.getElementById(id);
const esc=v=>String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
let session=null, profile=null, club=null;

function initials(name){
  return String(name||'CSP').trim().split(/\s+/).slice(0,2).map(x=>x[0]||'').join('').toUpperCase()||'CSP';
}
function fmtDate(v){
  if(!v)return 'Člen CSP';
  return 'Člen od '+new Date(v).toLocaleDateString('sk-SK',{month:'long',year:'numeric'});
}
function todayRange(){
  const a=new Date();a.setHours(0,0,0,0);
  const b=new Date(a);b.setDate(b.getDate()+1);
  return [a.toISOString(),b.toISOString()];
}
function openSettings(){
  $('settingsName').value=club?.name||profile?.full_name||'';
  $('settingsBio').value=profile?.bio||'';
  $('settingsOverlay').classList.add('show');
}
function closeSettings(){ $('settingsOverlay').classList.remove('show'); }
function renderIdentity(){
  const name=club?.name||profile?.full_name||'Klub';
  $('profileName').textContent=name;
  $('accountName').textContent=name;
  $('profileInitials').textContent=initials(name);
  $('accountAvatar').textContent=initials(name);
  $('memberSince').textContent=fmtDate(profile?.created_at);
  $('profileQuote').textContent=profile?.bio ? '„'+profile.bio+'“' : '„Všetko okolo klubu v jednom systéme.“';
  const location=[profile?.city,profile?.country_code].filter(Boolean).join(', ');
  $('profileLocationLine').textContent=location||'Klubový účet';
  $('profileLocation').textContent=location||'Connect Sports Pro';
  if(profile?.avatar_url){
    $('profileAvatar').src=profile.avatar_url;
    $('profileAvatar').hidden=false;
    $('profilePortrait').classList.add('has-image');
  }
}
function renderActivity(tournaments,reservations){
  const items=[];
  (tournaments||[]).slice(0,3).forEach(t=>items.push({
    icon:'🏆',title:t.name||'Turnaj',body:[t.sport,t.status].filter(Boolean).join(' · '),time:t.date||t.created_at
  }));
  (reservations||[]).slice(0,3).forEach(r=>items.push({
    icon:'▣',title:r.customer_name||'Rezervácia',body:[r.station_name_snapshot,r.source].filter(Boolean).join(' · '),time:r.starts_at
  }));
  items.sort((a,b)=>new Date(b.time||0)-new Date(a.time||0));
  $('activityList').innerHTML=items.length?items.slice(0,5).map(x=>`<div class="activity-row"><span class="activity-symbol">${esc(x.icon)}</span><div><b>${esc(x.title)}</b><p>${esc(x.body||'')}</p></div><time>${x.time?new Date(x.time).toLocaleDateString('sk-SK'):'—'}</time></div>`).join(''):'<div class="empty-row">Zatiaľ bez zaznamenanej aktivity.</div>';
}
async function load(){
  const s=await auth.getSession();
  session=s.data?.session||null;
  if(!session){ location.replace('/login/?returnTo='+encodeURIComponent(location.pathname)); return; }

  const pr=await auth.getCurrentProfile(session.user);
  if(pr.error) throw pr.error;
  profile=pr.data||null;

  const role=String(profile?.role||'').toLowerCase();
  const plan=String(profile?.plan||'').toLowerCase();
  if(!(profile?.is_admin||role==='club'||role==='organization'||plan==='ultra'||plan==='elite')){
    location.replace('/profil/');
    return;
  }

  const clubRes=await auth.client.from('clubs').select('id,name,created_at').eq('owner_id',session.user.id).maybeSingle();
  if(clubRes.error) throw clubRes.error;
  club=clubRes.data||null;
  renderIdentity();

  if(!club){
    $('activityList').innerHTML='<div class="empty-row">Klub ešte nie je vytvorený. Otvor Club Manager a dokonči nastavenie.</div>';
    $('pageState').hidden=true;
    return;
  }

  const [todayStart,todayEnd]=todayRange();
  const [
    tournamentsRes,resCountRes,venuesRes,employeesRes,activeRes,nextRes,recentRes
  ]=await Promise.all([
    auth.client.from('tournaments').select('id,name,sport,status,date,created_at').eq('owner_id',session.user.id).order('created_at',{ascending:false}).limit(5),
    auth.client.from('reservations').select('id',{count:'exact',head:true}).eq('club_id',club.id).gte('starts_at',todayStart).lt('starts_at',todayEnd).neq('status','cancelled'),
    auth.client.from('venues').select('id',{count:'exact',head:true}).eq('club_id',club.id),
    auth.client.from('club_employees').select('id',{count:'exact',head:true}).eq('club_id',club.id).eq('is_active',true),
    auth.client.from('club_manager_live_sessions').select('id,station_id,status').eq('club_id',club.id).in('status',['running','paused']),
    auth.client.from('reservations').select('id,starts_at,customer_name,station_name_snapshot,source').eq('club_id',club.id).gte('starts_at',new Date().toISOString()).neq('status','cancelled').order('starts_at',{ascending:true}).limit(1),
    auth.client.from('reservations').select('id,starts_at,customer_name,station_name_snapshot,source').eq('club_id',club.id).order('starts_at',{ascending:false}).limit(5)
  ]);

  const errors=[tournamentsRes,resCountRes,venuesRes,employeesRes,activeRes,nextRes,recentRes].map(x=>x.error).filter(Boolean);
  if(errors.length) console.warn('[profil-ul] partial data errors',errors);

  const tournaments=tournamentsRes.data||[];
  const reservationsToday=Number(resCountRes.count||0);
  const venues=Number(venuesRes.count||0);
  const employees=Number(employeesRes.count||0);
  const active=activeRes.data||[];
  const next=nextRes.data?.[0]||null;

  $('statTournaments').textContent=String(tournaments.length);
  $('statReservations').textContent=String(reservationsToday);
  $('statVenues').textContent=String(venues);
  $('activeStations').textContent=String(active.length);
  $('stationSummary').textContent=active.length?active.length+' aktívnych staníc':'Žiadne aktívne stanice';
  $('todayReservations').textContent=String(reservationsToday);
  $('nextReservation').textContent=next?'Najbližšia '+new Date(next.starts_at).toLocaleTimeString('sk-SK',{hour:'2-digit',minute:'2-digit'}):'Bez ďalšej rezervácie';
  $('employeeCount').textContent=String(employees);
  $('rightStations').textContent=String(venues);
  $('rightReservations').textContent=String(reservationsToday);

  const utilization=venues?Math.min(100,Math.round(active.length/venues*100)):0;
  $('utilizationBar').style.width=utilization+'%';
  $('utilizationLabel').textContent=utilization+'%';

  renderActivity(tournaments,recentRes.data||[]);
  $('pageState').hidden=true;
}

$('menuToggle')?.addEventListener('click',()=>$('sidebar').classList.toggle('open'));
document.querySelectorAll('[data-route]').forEach(b=>b.addEventListener('click',()=>{location.href=b.dataset.route}));
$('globalSearch')?.addEventListener('submit',e=>{e.preventDefault();const q=$('globalSearchInput').value.trim();if(q)location.href='/search/?q='+encodeURIComponent(q)});
$('accountToggle')?.addEventListener('click',e=>{if(e.target.closest('.notification'))return;e.stopPropagation();$('accountMenu').classList.toggle('show')});
document.addEventListener('click',e=>{if(!e.target.closest('#accountToggle'))$('accountMenu')?.classList.remove('show')});
$('profileSettingsBtn')?.addEventListener('click',e=>{e.stopPropagation();$('accountMenu').classList.remove('show');openSettings()});
$('editProfile')?.addEventListener('click',openSettings);
$('settingsCancel')?.addEventListener('click',closeSettings);
$('settingsOverlay')?.addEventListener('click',e=>{if(e.target===e.currentTarget)closeSettings()});
$('settingsSave')?.addEventListener('click',async()=>{
  const btn=$('settingsSave');btn.disabled=true;btn.textContent='Ukladám…';
  try{
    const name=$('settingsName').value.trim(),bio=$('settingsBio').value.trim();
    const {error}=await auth.client.from('profiles').update({full_name:name||null,bio:bio||null}).eq('id',session.user.id);
    if(error)throw error;
    profile.full_name=name||profile.full_name;profile.bio=bio||null;
    if(club&&name){
      const {error:clubError}=await auth.client.from('clubs').update({name}).eq('id',club.id);
      if(clubError)throw clubError;
      club.name=name;
    }
    renderIdentity();closeSettings();
  }catch(err){alert(err.message||'Profil sa nepodarilo uložiť.')}
  finally{btn.disabled=false;btn.textContent='Uložiť'}
});
$('logoutBtn')?.addEventListener('click',async()=>{await auth.signOut();location.replace('/login/')});

load().catch(err=>{
  console.error('[profil-ul]',err);
  $('pageState').textContent='Profil sa nepodarilo načítať.';
});
})();