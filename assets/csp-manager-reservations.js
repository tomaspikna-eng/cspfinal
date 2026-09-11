(function () {
  'use strict';

  const $ = id => document.getElementById(id);
  const esc = value => String(value ?? '').replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[ch]));
  const SPORT_ICON = {billiard:'🎱',darts:'🎯',bowling:'🎳',cards:'🃏'};
  const HOURS = Array.from({length:14},(_,index)=>10+index);
  const today = new Date().toISOString().slice(0,10);
  let context = null;
  let stations = [];
  let reservations = [];
  let customerHistory = [];
  let currentSport = null;
  let pick = null;

  function slotStart(date,hour) { return new Date(`${date}T${String(hour).padStart(2,'0')}:00:00`); }
  function stationSport(station) { return String(station.sport || 'iné').toLowerCase(); }
  function findReservation(stationId,date,hour) {
    const start=slotStart(date,hour), end=new Date(start.getTime()+3600000);
    return reservations.find(item => item.station_id===stationId && item.status!=='cancelled' && new Date(item.starts_at)<end && new Date(item.ends_at)>start) || null;
  }

  function toast(message,isError) {
    const el=$('toast'); el.textContent=message; el.className=`toast show${isError?' err':''}`;
    setTimeout(()=>{el.className=`toast${isError?' err':''}`;},2400);
  }

  function buildSportTabs() {
    const root=$('sportTabs');
    const sports=[...new Set(stations.map(stationSport))];
    if(!sports.length){currentSport=null;root.replaceChildren();$('gridArea').innerHTML='<div class="empty">Zatiaľ nemáš pridané športoviská. <a href="/manager/sportoviska/" style="color:var(--gold)">Pridať prvé →</a></div>';return;}
    if(!sports.includes(currentSport))currentSport=sports[0];
    root.replaceChildren(...sports.map(sport=>{
      const button=document.createElement('button');button.type='button';button.className=`sport-tab${sport===currentSport?' active':''}`;
      button.textContent=`${SPORT_ICON[sport]||'🏆'} ${sport}`;
      button.onclick=()=>{currentSport=sport;buildSportTabs();renderGrid();};
      return button;
    }));
  }

  function renderGrid() {
    const date=$('dateInput').value;
    const list=stations.filter(station=>stationSport(station)===currentSport);
    if(!list.length){$('gridArea').innerHTML='<div class="empty">Žiadne športoviská v tejto kategórii.</div>';return;}
    const head=HOURS.map(hour=>`<th>${String(hour).padStart(2,'0')}:00</th>`).join('');
    const rows=list.map(station=>{
      const cells=HOURS.map(hour=>{
        const reservation=findReservation(station.id,date,hour);
        const maintenance=station.is_active===false||station.status==='maintenance';
        const past=slotStart(date,hour).getTime()<Date.now();
        let cls='free',text='+',title='Voľné — rezervovať',disabled='';
        if(reservation){cls='busy';text='●';title=`${reservation.customer_name||'Rezervácia'} (${reservation.party_size||1} os.)`;disabled='disabled';}
        else if(maintenance){cls='maint';text='—';title='Mimo prevádzky';disabled='disabled';}
        else if(past){cls='past';text='·';title='V minulosti';disabled='disabled';}
        return `<td><button type="button" class="slot ${cls}" title="${esc(title)}" ${disabled} data-slot-station="${esc(station.id)}" data-slot-hour="${hour}">${text}</button></td>`;
      }).join('');
      return `<tr><th>${SPORT_ICON[stationSport(station)]||'🏆'} ${esc(station.name)}</th>${cells}</tr>`;
    }).join('');
    $('gridArea').innerHTML=`<div class="grid-wrap"><table><thead><tr><th class="corner">Stôl / Hodina</th>${head}</tr></thead><tbody>${rows}</tbody></table></div>`;
  }

  function openModal(stationId,hour) {
    const station=stations.find(item=>item.id===stationId); if(!station)return;
    pick={station,hour};
    const date=$('dateInput').value;
    $('modalArea').innerHTML=`<div class="overlay" data-close-overlay><div class="modal" role="dialog" aria-modal="true" aria-labelledby="reservationTitle"><h2 id="reservationTitle">${esc(station.name)}</h2><p class="slot-meta">${esc(date)} · ${String(hour).padStart(2,'0')}:00 · ${(Number(station.base_hourly_rate)||0).toFixed(2)} € / hod</p><div class="form"><div class="row2"><div class="fld"><label for="mDuration">Dĺžka</label><select id="mDuration"><option value="60">1 hodina</option><option value="120">2 hodiny</option><option value="180">3 hodiny</option><option value="240">4 hodiny</option></select></div><div class="fld"><label for="mParty">Počet osôb</label><input type="number" id="mParty" min="1" max="20" value="2"></div></div><div class="fld"><label for="mPhone">Telefón *</label><input id="mPhone" placeholder="0905 …" maxlength="30"></div><p class="found hidden" id="mFound">✓ Existujúci zákazník</p><div class="fld"><label for="mName">Meno *</label><input id="mName" maxlength="100"></div><div class="fld"><label for="mEmail">E-mail</label><input type="email" id="mEmail" maxlength="255"></div><div class="fld"><label for="mNotes">Interná poznámka</label><textarea id="mNotes" rows="2" maxlength="500"></textarea></div><div class="modal-actions"><button class="btn btn-cancel" type="button" data-close-modal>Zrušiť</button><button class="btn btn-confirm" type="button" data-submit-reservation>Potvrdiť rezerváciu</button></div></div></div></div>`;
    $('mPhone').addEventListener('input',lookupCustomer);
    $('mName').focus();
  }

  function closeModal(){ $('modalArea').replaceChildren(); pick=null; }

  function lookupCustomer(){
    const query=$('mPhone').value.replace(/\s/g,'');
    const match=query.length>=3?customerHistory.find(item=>String(item.customer_phone||'').replace(/\s/g,'').includes(query)):null;
    $('mFound').classList.toggle('hidden',!match);
    if(match){if(!$('mName').value)$('mName').value=match.customer_name||'';if(!$('mEmail').value)$('mEmail').value=match.customer_email||'';}
  }

  async function submitReservation(){
    if(!pick)return;
    const selected={station:pick.station,hour:pick.hour};
    const date=$('dateInput').value,name=$('mName').value.trim(),phone=$('mPhone').value.trim(),email=$('mEmail').value.trim(),note=$('mNotes').value.trim();
    const party=Number($('mParty').value),duration=Number($('mDuration').value);
    if(!name||!phone){toast('Vyplň meno a telefón.',true);return;}
    if(!Number.isInteger(party)||party<1||party>20){toast('Počet osôb musí byť od 1 do 20.',true);return;}
    const startsAt=slotStart(date,selected.hour),endsAt=new Date(startsAt.getTime()+duration*60000);
    if(reservations.some(item=>item.station_id===selected.station.id&&item.status!=='cancelled'&&new Date(item.starts_at)<endsAt&&new Date(item.ends_at)>startsAt)){toast('Tento termín je už obsadený.',true);return;}
    const button=document.querySelector('[data-submit-reservation]');button.disabled=true;
    const {error}=await cspAuth.client.rpc('club_manager_upsert_reservation',{p_reservation_id:null,p_club_id:context.club.id,p_station_id:selected.station.id,p_customer_name:name,p_customer_email:email||null,p_customer_phone:phone,p_party_size:party,p_starts_at:startsAt.toISOString(),p_ends_at:endsAt.toISOString(),p_internal_note:note||null,p_status:'confirmed'});
    if(error){console.error('[manager-reservations]',error);button.disabled=false;toast('Rezerváciu sa nepodarilo uložiť.',true);return;}
    const successLabel=`${selected.station.name}, ${String(selected.hour).padStart(2,'0')}:00`;
    closeModal();
    await loadReservations();
    renderGrid();
    toast(`Rezervácia potvrdená — ${successLabel}`);
  }

  async function loadReservations(){
    const date=$('dateInput').value;
    const start=new Date(`${date}T00:00:00`),end=new Date(start.getTime()+86400000);
    const {data,error}=await cspAuth.client.from('reservations').select('id,station_id,customer_name,customer_email,customer_phone,party_size,starts_at,ends_at,status').eq('club_id',context.club.id).lt('starts_at',end.toISOString()).gt('ends_at',start.toISOString()).order('starts_at');
    if(error)throw error;reservations=data||[];
  }

  async function loadData(){
    const [stationResult,historyResult]=await Promise.all([
      cspAuth.client.from('stations').select('id,name,sport,status,is_active,base_hourly_rate,sort_order').eq('club_id',context.club.id).order('sort_order').order('name'),
      cspAuth.client.from('reservations').select('customer_name,customer_email,customer_phone').eq('club_id',context.club.id).not('customer_phone','is',null).order('created_at',{ascending:false}).limit(300)
    ]);
    if(stationResult.error)throw stationResult.error;if(historyResult.error)throw historyResult.error;
    stations=stationResult.data||[];customerHistory=historyResult.data||[];await loadReservations();buildSportTabs();renderGrid();
  }

  document.addEventListener('click',event=>{
    const slot=event.target.closest('[data-slot-station]');if(slot&&!slot.disabled)openModal(slot.dataset.slotStation,Number(slot.dataset.slotHour));
    if(event.target.closest('[data-close-modal]'))closeModal();
    if(event.target.matches('[data-close-overlay]'))closeModal();
    if(event.target.closest('[data-submit-reservation]'))submitReservation();
  });
  $('dateInput').addEventListener('change',async()=>{try{await loadReservations();renderGrid();}catch(error){console.error(error);toast('Rezervácie sa nepodarilo načítať.',true);}});
  $('signOutBtn').addEventListener('click',()=>cspManager.signOut());
  window.toggleSidebar=function(){$('sidebar').classList.toggle('open');$('backdrop').classList.toggle('show');};
  $('dateInput').value=today;$('dateInput').min=today;

  (async function init(){
    context=await cspManager.requireClubManagerAccess();if(!context)return;
    $('tbClubName').textContent=context.club.name;
    const name=context.profile?.full_name||context.session.user.email||'Používateľ';$('tbUserName').textContent=name;$('tbUserAv').textContent=name.split(/\s+/).map(x=>x[0]).join('').slice(0,2).toUpperCase();
    try{await loadData();$('loadingGate').style.display='none';}catch(error){console.error('[manager-reservations]',error);$('loadingGate').innerHTML='<div class="gate-loading">Rezervácie sa nepodarilo načítať. Obnov stránku.</div>';}
  })();
})();
