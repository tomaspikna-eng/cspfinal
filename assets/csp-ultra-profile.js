(() => {
'use strict';

const auth=window.cspAuth;
if(!auth) return;

const $=id=>document.getElementById(id);
const esc=v=>String(v??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
let session=null, profile=null, club=null, venues=[], calendarReservations=[], calendarOffset=0;

const dayKeys=['mon','tue','wed','thu','fri','sat','sun'];
const dayLabels=['Po','Ut','St','Št','Pi','So','Ne'];
const dayInputIds=['settingsMon','settingsTue','settingsWed','settingsThu','settingsFri','settingsSat','settingsSun'];

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
function weekStart(base=new Date()){
  const d=new Date(base);d.setHours(0,0,0,0);
  const n=(d.getDay()+6)%7;d.setDate(d.getDate()-n);
  return d;
}
function openSettings(){
  $('settingsName').value=club?.name||profile?.full_name||'';
  $('settingsBio').value=profile?.bio||'';
  $('settingsAddress').value=club?.address_line1||'';
  $('settingsPostalCode').value=club?.postal_code||'';
  $('settingsCity').value=club?.city||'';
  $('settingsCountry').value=club?.country||'';
  const hours=club?.opening_hours||{};
  dayKeys.forEach((key,i)=>$(dayInputIds[i]).value=hours[key]||'');
  $('settingsOverlay').classList.add('show');
}
function closeSettings(){ $('settingsOverlay').classList.remove('show'); }

function renderIdentity(){
  const name=club?.name||profile?.full_name||'Klub';
  $('profileName').textContent=name;
  $('accountName').textContent=name;
  $('profileInitials').textContent=initials(name);
  $('accountAvatar').textContent=initials(name);
  $('memberSince').textContent=fmtDate(club?.created_at||profile?.created_at);
  $('profileQuote').textContent=profile?.bio ? '„'+profile.bio+'“' : '';
  const location=[club?.address_line1,club?.postal_code,club?.city,club?.country].filter(Boolean).join(', ');
  $('profileLocationLine').textContent=club?.city||club?.country||'Klubový účet';
  $('profileLocation').textContent=location||'Adresa nie je nastavená';
  if(profile?.avatar_url){
    $('profileAvatar').src=profile.avatar_url;
    $('profileAvatar').hidden=false;
    $('profilePortrait').classList.add('has-image');
  }
}

function renderActivity(tournaments,events){
  const items=[];
  (tournaments||[]).forEach(t=>items.push({
    icon:'🏆',title:t.name||'Turnaj',body:[t.sport,t.status].filter(Boolean).join(' · '),time:t.date||t.created_at
  }));
  (events||[]).forEach(e=>items.push({
    icon:'▣',title:e.title||'Udalosť',body:[e.sport,e.status].filter(Boolean).join(' · '),time:e.starts_at||e.created_at
  }));
  items.sort((a,b)=>new Date(b.time||0)-new Date(a.time||0));
  $('activityList').innerHTML=items.length?items.slice(0,5).map(x=>`<div class="activity-row"><span class="activity-symbol">${esc(x.icon)}</span><div><b>${esc(x.title)}</b><p>${esc(x.body||'')}</p></div><time>${x.time?new Date(x.time).toLocaleDateString('sk-SK'):'—'}</time></div>`).join(''):'<div class="empty-row">Zatiaľ bez udalostí alebo turnajov.</div>';
}

function renderVenues(){
  $('venueList').innerHTML=venues.length?venues.slice(0,5).map(v=>`<a class="venue-row" href="https://cspmanager.app/venues/"><span class="venue-icon">◎</span><span><b>${esc(v.name||'Športovisko')}</b><span>${esc([v.sport,v.description].filter(Boolean).join(' · ')||'Bez popisu')}</span></span><span class="venue-state">${v.is_active===false?'NEAKTÍVNE':'AKTÍVNE'}</span></a>`).join(''):'<div class="empty-row">Žiadne športoviská.</div>';
}

function renderReservationCalendar(){
  const start=weekStart();
  start.setDate(start.getDate()+calendarOffset*7);
  const end=new Date(start);end.setDate(end.getDate()+7);
  $('calendarTitle').textContent=start.toLocaleDateString('sk-SK',{day:'numeric',month:'short'})+' – '+new Date(end.getTime()-86400000).toLocaleDateString('sk-SK',{day:'numeric',month:'short'});
  const today=new Date();today.setHours(0,0,0,0);

  const days=[];
  for(let i=0;i<7;i++){
    const d=new Date(start);d.setDate(d.getDate()+i);
    const next=new Date(d);next.setDate(next.getDate()+1);
    const count=calendarReservations.filter(r=>{
      const x=new Date(r.starts_at);
      return x>=d&&x<next&&r.status!=='cancelled';
    }).length;
    days.push(`<div class="reservation-day ${d.getTime()===today.getTime()?'today':''}"><span>${dayLabels[i]}</span><b>${d.getDate()}</b><small>${count} rez.</small></div>`);
  }
  $('reservationWeek').innerHTML=days.join('');

  const rows=calendarReservations.filter(r=>{
    const x=new Date(r.starts_at);
    return x>=start&&x<end&&r.status!=='cancelled';
  }).sort((a,b)=>new Date(a.starts_at)-new Date(b.starts_at));

  $('calendarReservationCount').textContent=String(rows.length);
  $('publicReservationList').innerHTML=rows.length?rows.slice(0,8).map(r=>{
    const d=new Date(r.starts_at);
    return `<div class="public-reservation"><time>${d.toLocaleDateString('sk-SK',{weekday:'short'})}<br>${d.toLocaleTimeString('sk-SK',{hour:'2-digit',minute:'2-digit'})}</time><div><b>${esc(r.station_name_snapshot||'Rezervácia')}</b><span>${esc(r.customer_name||'Obsadené')}</span></div></div>`;
  }).join(''):'<div class="empty-row">V tomto týždni nie sú rezervácie.</div>';
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

  const clubRes=await auth.client.from('clubs')
    .select('id,name,created_at,address_line1,postal_code,city,country,opening_hours')
    .eq('owner_id',session.user.id).maybeSingle();
  if(clubRes.error) throw clubRes.error;
  club=clubRes.data||null;
  renderIdentity();

  if(!club){
    $('activityList').innerHTML='<div class="empty-row">Klub ešte nie je vytvorený.</div>';
    $('pageState').hidden=true;
    return;
  }

  const [todayStart,todayEnd]=todayRange();
  const calFrom=weekStart();calFrom.setDate(calFrom.getDate()-7);
  const calTo=new Date(calFrom);calTo.setDate(calTo.getDate()+49);

  const [
    tournamentsRes,eventsRes,resCountRes,venuesRes,employeesRes,activeRes,nextRes,calendarRes
  ]=await Promise.all([
    auth.client.from('tournaments').select('id,name,sport,status,date,created_at').eq('owner_id',session.user.id).order('created_at',{ascending:false}).limit(8),
    auth.client.from('events').select('id,title,sport,status,starts_at,created_at').or('club_id.eq.'+club.id+',owner_id.eq.'+session.user.id).order('starts_at',{ascending:false}).limit(8),
    auth.client.from('reservations').select('id',{count:'exact',head:true}).eq('club_id',club.id).gte('starts_at',todayStart).lt('starts_at',todayEnd).neq('status','cancelled'),
    auth.client.from('venues').select('id,name,sport,description,is_active').eq('club_id',club.id).order('created_at',{ascending:true}),
    auth.client.from('club_employees').select('id',{count:'exact',head:true}).eq('club_id',club.id).eq('is_active',true),
    auth.client.from('club_manager_live_sessions').select('id,station_id,status').eq('club_id',club.id).in('status',['running','paused']),
    auth.client.from('reservations').select('id,starts_at,station_name_snapshot').eq('club_id',club.id).gte('starts_at',new Date().toISOString()).neq('status','cancelled').order('starts_at',{ascending:true}).limit(1),
    auth.client.from('reservations').select('id,starts_at,customer_name,station_name_snapshot,status').eq('club_id',club.id).gte('starts_at',calFrom.toISOString()).lt('starts_at',calTo.toISOString()).order('starts_at',{ascending:true})
  ]);

  const all=[tournamentsRes,eventsRes,resCountRes,venuesRes,employeesRes,activeRes,nextRes,calendarRes];
  const errors=all.map(x=>x.error).filter(Boolean);
  if(errors.length) console.warn('[profil-ul] partial data errors',errors);

  const tournaments=tournamentsRes.data||[];
  const events=eventsRes.data||[];
  venues=venuesRes.data||[];
  calendarReservations=calendarRes.data||[];
  const reservationsToday=Number(resCountRes.count||0);
  const employees=Number(employeesRes.count||0);
  const active=activeRes.data||[];
  const next=nextRes.data?.[0]||null;

  $('statTournaments').textContent=String(tournaments.length);
  $('statReservations').textContent=String(reservationsToday);
  $('statVenues').textContent=String(venues.length);
  $('activeStations').textContent=String(active.length);
  $('stationSummary').textContent=active.length?active.length+' aktívnych staníc':'Žiadne aktívne stanice';
  $('todayReservations').textContent=String(reservationsToday);
  $('nextReservation').textContent=next?'Najbližšia '+new Date(next.starts_at).toLocaleTimeString('sk-SK',{hour:'2-digit',minute:'2-digit'}):'Bez ďalšej rezervácie';
  $('employeeCount').textContent=String(employees);

  renderActivity(tournaments,events);
  renderVenues();
  renderReservationCalendar();
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
$('calendarPrev')?.addEventListener('click',()=>{calendarOffset=Math.max(-1,calendarOffset-1);renderReservationCalendar()});
$('calendarNext')?.addEventListener('click',()=>{calendarOffset=Math.min(5,calendarOffset+1);renderReservationCalendar()});

$('settingsSave')?.addEventListener('click',async()=>{
  const btn=$('settingsSave');btn.disabled=true;btn.textContent='Ukladám…';
  try{
    const name=$('settingsName').value.trim(),bio=$('settingsBio').value.trim();
    const opening_hours={};
    dayKeys.forEach((key,i)=>{const v=$(dayInputIds[i]).value.trim();if(v)opening_hours[key]=v;});

    const {error}=await auth.client.from('profiles').update({full_name:name||null,bio:bio||null}).eq('id',session.user.id);
    if(error)throw error;

    const clubPatch={
      name:name||club.name,
      address_line1:$('settingsAddress').value.trim()||null,
      postal_code:$('settingsPostalCode').value.trim()||null,
      city:$('settingsCity').value.trim()||null,
      country:$('settingsCountry').value.trim()||null,
      opening_hours
    };
    const {data:updated,error:clubError}=await auth.client.from('clubs').update(clubPatch).eq('id',club.id).select('id,name,created_at,address_line1,postal_code,city,country,opening_hours').single();
    if(clubError)throw clubError;

    profile.full_name=name||profile.full_name;profile.bio=bio||null;
    club=updated;
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