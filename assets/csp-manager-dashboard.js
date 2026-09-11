(function () {
  'use strict';

  const $ = id => document.getElementById(id);
  const esc = value => String(value ?? '').replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[ch]));
  const SPORT_ICON = {billiard:'🎱',darts:'🎯',bowling:'🎳',cards:'🃏'};
  const SPORT_LABEL = {billiard:'Biliard',darts:'Šípky',bowling:'Bowling',cards:'Karty'};
  let stations = [];
  let sessions = [];
  let reservations = [];
  let priceProfiles = [];

  function fmtDuration(startedAt, accumulatedSeconds) {
    const start = new Date(startedAt).getTime();
    const elapsed = Number.isFinite(start) ? Math.max(0, Math.floor((Date.now() - start) / 1000)) : 0;
    const total = elapsed + (Number(accumulatedSeconds) || 0);
    const h = Math.floor(total / 3600), m = Math.floor(total % 3600 / 60), s = total % 60;
    return [h,m,s].map(n => String(n).padStart(2,'0')).join(':');
  }

  function activeSession(stationId) {
    return sessions.find(item => item.station_id === stationId && ['running','paused'].includes(item.status));
  }

  function renderStations() {
    const root = $('stations');
    if (!stations.length) {
      root.innerHTML = '<p class="empty">Zatiaľ nie sú vytvorené žiadne športoviská. <a href="/manager/sportoviska/" style="color:var(--gold)">Pridať prvé →</a></p>';
      return;
    }
    root.innerHTML = stations.map(station => {
      const session = activeSession(station.id);
      const status = station.is_active === false || station.status === 'maintenance' ? 'maintenance' : session ? 'occupied' : 'available';
      const icon = SPORT_ICON[station.sport] || '🏆';
      const label = SPORT_LABEL[station.sport] || station.sport || 'Šport';
      const action = session
        ? `<div class="station-timer" data-started="${esc(session.started_at)}" data-accumulated="${Number(session.accumulated_seconds)||0}">00:00:00</div><button class="btn-block btn-end" data-stop-session="${esc(session.id)}">Ukončiť hru</button>`
        : `<button class="btn-block btn-start" data-start-station="${esc(station.id)}" ${status==='maintenance'?'disabled':''}>Spustiť hru</button>`;
      const scoreboard = ['billiard','darts'].includes(station.sport)
        ? `<button class="btn-block btn-scoreboard" data-scoreboard-station="${esc(station.id)}">🖥️ Otvoriť scoreboard</button>` : '';
      return `<div class="station"><div class="station-top"><div><div class="station-icon">${icon}</div><div class="station-name">${esc(station.name)}</div><div class="station-sport">${esc(label)}</div></div><span class="badge ${status}">${status==='occupied'?'Obsadené':status==='maintenance'?'Mimo prevádzky':'Voľné'}</span></div>${action}${scoreboard}</div>`;
    }).join('');
  }

  function renderReservations() {
    const root = $('reservations');
    if (!reservations.length) {
      root.innerHTML = '<p class="empty">Žiadne pripravované rezervácie.</p>';
      return;
    }
    const rows = reservations.map(item => {
      const station = stations.find(s => s.id === item.station_id);
      const from = new Date(item.starts_at).toLocaleString('sk-SK',{day:'2-digit',month:'2-digit',hour:'2-digit',minute:'2-digit'});
      const to = new Date(item.ends_at).toLocaleString('sk-SK',{hour:'2-digit',minute:'2-digit'});
      return `<tr><td class="station-cell">${esc(station?.name || '—')}</td><td>${esc(item.customer_name || '—')}</td><td class="muted">${esc(item.customer_phone || '—')}</td><td>${esc(from)}</td><td>${esc(to)}</td></tr>`;
    }).join('');
    root.innerHTML = `<div class="table-wrap"><table><thead><tr><th>Športovisko</th><th>Zákazník</th><th>Telefón</th><th>Od</th><th>Do</th></tr></thead><tbody>${rows}</tbody></table></div>`;
  }

  function renderStats() {
    const active = sessions.filter(item => ['running','paused'].includes(item.status));
    $('statOccupied').textContent = `${active.length} / ${stations.length}`;
    $('statSessions').textContent = String(active.length);
    $('statCalls').textContent = '0';
    $('statCallsCard').classList.remove('alert');
    $('callsBox').innerHTML = '';
  }

  function renderAll() {
    renderStats();
    renderStations();
    renderReservations();
    tickTimers();
  }

  function tickTimers() {
    document.querySelectorAll('.station-timer').forEach(el => {
      el.textContent = fmtDuration(el.dataset.started, Number(el.dataset.accumulated));
    });
  }

  async function loadData(clubId) {
    const now = new Date().toISOString();
    const limit = new Date(Date.now() + 7 * 86400000).toISOString();
    const [stationResult, sessionResult, reservationResult, profileResult] = await Promise.all([
      cspAuth.client.from('stations').select('id,name,sport,status,is_active,sort_order').eq('club_id',clubId).order('sort_order').order('name'),
      cspAuth.client.from('club_manager_live_sessions').select('id,station_id,status,started_at,accumulated_seconds').eq('club_id',clubId).in('status',['running','paused']),
      cspAuth.client.from('reservations').select('id,station_id,customer_name,customer_phone,starts_at,ends_at,status').eq('club_id',clubId).gte('starts_at',now).lt('starts_at',limit).in('status',['pending','confirmed']).order('starts_at').limit(30),
      cspAuth.client.from('club_manager_price_profiles').select('code,name').eq('club_id',clubId).eq('is_active',true).order('sort_order')
    ]);
    for (const result of [stationResult,sessionResult,reservationResult,profileResult]) if (result.error) throw result.error;
    stations = stationResult.data || [];
    sessions = sessionResult.data || [];
    reservations = reservationResult.data || [];
    priceProfiles = profileResult.data || [];
  }

  async function startSession(stationId) {
    const priceCode = priceProfiles[0]?.code || 'standard';
    const {error} = await cspAuth.client.rpc('club_manager_start_session',{p_station_id:stationId,p_price_profile_code:priceCode});
    if (error) throw error;
  }

  async function stopSession(sessionId) {
    const {error} = await cspAuth.client.rpc('club_manager_stop_session',{p_session_id:sessionId});
    if (error) throw error;
  }

  function openScoreboard(stationId) {
    const station = stations.find(item => item.id === stationId);
    if (!station) return;
    const params = new URLSearchParams({station:station.name,sport:station.sport || 'billiard',race:'5',players:'2',from:location.href});
    window.open(`/scoreboard/?${params}`,'_blank','noopener');
  }

  function showError(error) {
    console.error('[manager-dashboard]',error);
    alert('Operáciu sa nepodarilo dokončiť. Skúste to znova.');
  }

  document.addEventListener('click', async event => {
    const start = event.target.closest('[data-start-station]');
    const stop = event.target.closest('[data-stop-session]');
    const scoreboard = event.target.closest('[data-scoreboard-station]');
    if (scoreboard) return openScoreboard(scoreboard.dataset.scoreboardStation);
    if (!start && !stop) return;
    const button = start || stop;
    button.disabled = true;
    try {
      if (start) await startSession(start.dataset.startStation);
      else await stopSession(stop.dataset.stopSession);
      const ctx = await cspManager.requireClubManagerAccess();
      if (!ctx) return;
      await loadData(ctx.club.id);
      renderAll();
    } catch (error) { showError(error); }
    finally { button.disabled = false; }
  });

  window.toggleSidebar = function () {
    $('sidebar').classList.toggle('open');
    $('backdrop').classList.toggle('show');
  };

  setInterval(tickTimers,1000);
  setInterval(() => { if ($('clock')) $('clock').textContent = new Date().toLocaleTimeString('sk-SK'); },1000);

  (async function init() {
    const ctx = await cspManager.requireClubManagerAccess({allowNoClub:true});
    if (!ctx) return;
    const name = ctx.profile?.full_name || ctx.session.user.email || 'Používateľ';
    document.querySelector('.tb-title .club').textContent = ctx.club?.name || 'Club Manager';
    document.querySelector('.tb-user').innerHTML = `<span class="tb-av">${esc(name.split(/\s+/).map(x=>x[0]).join('').slice(0,2).toUpperCase())}</span>${esc(name)}`;
    document.querySelector('.sb-signout').onclick = () => cspManager.signOut();
    if (!ctx.club) {
      $('stations').innerHTML = '<p class="empty">K účtu zatiaľ nie je priradený klub.</p>';
      $('reservations').innerHTML = '<p class="empty">Rezervácie sa zobrazia po vytvorení klubu.</p>';
      renderStats();
      return;
    }
    try { await loadData(ctx.club.id); renderAll(); }
    catch (error) { showError(error); }
  })();
})();
