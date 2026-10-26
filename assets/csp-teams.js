
(function(){
'use strict';
var $=function(id){return document.getElementById(id)};
var esc=function(v){return String(v==null?'':v).replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]})};
var allowedPlans=new Set(['pro_plus','ultra']);
var state={session:null,profile:null,teams:[],members:[],competitions:[],competitionTeams:[],meetings:[],games:[],selectedCompetition:null,editingMeeting:null};
var uiBound=false;

function toast(message,error){
  var el=$('toast');el.textContent=message;el.classList.toggle('error',!!error);el.classList.add('show');
  clearTimeout(toast.t);toast.t=setTimeout(function(){el.classList.remove('show')},2600);
}
function openModal(id){$(id).classList.add('open')}
function closeModal(id){$(id).classList.remove('open')}
function fmtDate(v){if(!v)return 'Bez termínu';try{return new Intl.DateTimeFormat('sk-SK',{day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'}).format(new Date(v))}catch(_){return 'Bez termínu'}}
function planLabel(p){return p==='pro_plus'?'PRO+':p==='ultra'?'ULTRA':String(p||'').toUpperCase()}
function teamById(id){return state.teams.find(function(x){return x.id===id})}
function competitionById(id){return state.competitions.find(function(x){return x.id===id})}
function membersFor(teamId){return state.members.filter(function(x){return x.team_id===teamId&&x.active}).sort(function(a,b){return (a.sort_order||0)-(b.sort_order||0)||a.display_name.localeCompare(b.display_name)})}
function compTeamIds(compId){return state.competitionTeams.filter(function(x){return x.competition_id===compId}).map(function(x){return x.team_id})}
function gamesFor(meetingId){return state.games.filter(function(x){return x.meeting_id===meetingId}).sort(function(a,b){return a.slot_no-b.slot_no})}

async function init(){
  try{
    var sr=await cspAuth.getSession(),session=sr.data&&sr.data.session;
    if(!session){location.href='/login/';return}
    state.session=session;
    var pr=await cspAuth.getCurrentProfile(session.user);
    if(pr.error)throw pr.error;
    state.profile=pr.data;
    $('accountName').textContent=(pr.data&&pr.data.full_name)||session.user.email||'CSP';
    $('planBadge').textContent=planLabel(pr.data&&pr.data.plan);
    if(!allowedPlans.has(pr.data&&pr.data.plan)){$('app').hidden=true;$('locked').hidden=false;return}
    $('locked').hidden=true;
    $('app').hidden=false;
    bind();
    await loadAll();
  }catch(err){console.error('[teams] init failed',err);toast((err&&err.message)||'Teams sa nepodarilo načítať.',true)}
}

function bind(){
  if(uiBound)return;
  uiBound=true;
  $('newTeamBtn').onclick=function(){$('teamForm').reset();openModal('teamModal')};
  $('newCompetitionBtn').onclick=openCompetitionModal;
  $('newMeetingBtn').onclick=function(){openMeetingModal()};
  document.querySelectorAll('[data-close]').forEach(function(b){b.onclick=function(){closeModal(b.dataset.close)}});
  document.querySelectorAll('.modal').forEach(function(m){m.addEventListener('click',function(e){if(e.target===m)closeModal(m.id)})});
  $('teamForm').addEventListener('submit',saveTeam);
  $('memberForm').addEventListener('submit',saveMember);
  $('competitionForm').addEventListener('submit',saveCompetition);
  $('meetingForm').addEventListener('submit',saveMeeting);
  $('meetingCompetition').addEventListener('change',syncMeetingTeams);
  $('rankingCompetition').addEventListener('change',function(e){state.selectedCompetition=e.target.value||null;renderRankings()});
  $('teamsGrid').addEventListener('click',handleTeamAction);
  $('competitionsGrid').addEventListener('click',handleCompetitionAction);
  $('meetingsList').addEventListener('click',handleMeetingAction);
  $('duelList').addEventListener('click',handleDuelAction);
  $('logoutBtn').onclick=async function(){await cspAuth.signOut();location.href='/'};
  document.querySelectorAll('[data-tab]').forEach(function(btn){btn.onclick=function(){
    document.querySelectorAll('[data-tab]').forEach(function(x){x.classList.toggle('active',x===btn)});
    document.querySelectorAll('[data-panel]').forEach(function(x){x.hidden=x.dataset.panel!==btn.dataset.tab});
  }});
}

async function loadAll(){
  var c=cspAuth.client;
  var rr=await Promise.all([
    c.from('teams').select('id,owner_id,name,short_name,sport,city,country,logo_url,status,created_at,updated_at').order('created_at',{ascending:false}),
    c.from('team_members').select('id,team_id,user_id,display_name,member_role,sort_order,active,created_at,updated_at').order('sort_order'),
    c.from('team_competitions').select('id,owner_id,name,sport,season_name,status,default_best_of,default_discipline,default_race_to,win_points,loss_points,created_at,updated_at').order('created_at',{ascending:false}),
    c.from('team_competition_teams').select('competition_id,team_id,seed,created_at'),
    c.from('team_meetings').select('id,competition_id,round_label,scheduled_at,home_team_id,away_team_id,best_of,status,home_score,away_score,winner_team_id,created_at,updated_at').order('created_at',{ascending:false}),
    c.from('team_match_games').select('id,meeting_id,slot_no,discipline,race_to,home_member_id,away_member_id,home_score,away_score,status,winner_member_id,winner_team_id,completed_at,created_at,updated_at').order('slot_no')
  ]);
  rr.forEach(function(r){if(r.error)throw r.error});
  state.teams=rr[0].data||[];state.members=rr[1].data||[];state.competitions=rr[2].data||[];
  state.competitionTeams=rr[3].data||[];state.meetings=rr[4].data||[];state.games=rr[5].data||[];
  if(!state.selectedCompetition||!state.competitions.some(function(x){return x.id===state.selectedCompetition}))state.selectedCompetition=state.competitions[0]&&state.competitions[0].id||null;
  renderAll();
}

function renderAll(){
  $('teamCount').textContent=state.teams.length;
  $('competitionCount').textContent=state.competitions.filter(function(x){return x.status==='active'}).length;
  $('meetingCount').textContent=state.meetings.length;
  $('duelCount').textContent=state.games.filter(function(x){return x.status==='completed'}).length;
  renderTeams();renderCompetitions();renderMeetings();renderRankingSelector();renderRankings();
}

function renderTeams(){
  var el=$('teamsGrid');
  if(!state.teams.length){el.innerHTML='<div class="empty">Zatiaľ nemáš vytvorený žiadny tím.</div>';return}
  el.innerHTML=state.teams.map(function(t){
    var ms=membersFor(t.id),cap=ms.find(function(m){return m.member_role==='captain'});
    var roster=ms.length?ms.map(function(m){return '<div class="roster-row"><span>'+esc(m.display_name)+'</span><em>'+(m.member_role==='captain'?'Kapitán':m.member_role==='substitute'?'Náhradník':'Hráč')+'</em></div>'}).join(''):'<div class="muted">Súpiska je prázdna.</div>';
    return '<article class="team-card"><div class="team-card-head"><div class="team-mark">'+esc((t.short_name||t.name).slice(0,3).toUpperCase())+'</div><div><h3>'+esc(t.name)+'</h3><p>'+esc(t.sport)+(t.city?' · '+esc(t.city):'')+(t.country?' · '+esc(t.country):'')+'</p></div><span class="status '+esc(t.status)+'">'+esc(t.status)+'</span></div><div class="team-meta"><span><b>'+ms.length+'</b> hráčov</span><span>Kapitán: <b>'+esc(cap?cap.display_name:'—')+'</b></span></div><div class="roster">'+roster+'</div><button class="btn small" data-add-member="'+t.id+'">+ Pridať hráča</button></article>';
  }).join('');
}

function renderCompetitions(){
  var el=$('competitionsGrid');
  if(!state.competitions.length){el.innerHTML='<div class="empty">Zatiaľ nemáš vytvorenú tímovú súťaž.</div>';return}
  el.innerHTML=state.competitions.map(function(c){
    var names=compTeamIds(c.id).map(function(id){var t=teamById(id);return t&&(t.short_name||t.name)}).filter(Boolean);
    return '<article class="competition-card"><div class="competition-top"><div><span class="eyebrow">'+esc(c.season_name||'Tímová súťaž')+'</span><h3>'+esc(c.name)+'</h3></div><span class="status '+esc(c.status)+'">'+esc(c.status)+'</span></div><p>'+esc(c.sport)+' · Best of '+c.default_best_of+' duelov · '+esc(c.default_discipline)+' · Race to '+c.default_race_to+'</p><div class="team-chips">'+(names.length?names.map(function(n){return '<span>'+esc(n)+'</span>'}).join(''):'<span>Bez tímov</span>')+'</div><button class="btn small ghost" data-comp-meeting="'+c.id+'">+ Stretnutie</button></article>';
  }).join('');
}

function renderMeetings(){
  var el=$('meetingsList');
  if(!state.meetings.length){el.innerHTML='<div class="empty">Zatiaľ nie sú vytvorené tímové stretnutia.</div>';return}
  el.innerHTML=state.meetings.map(function(m){
    var home=teamById(m.home_team_id),away=teamById(m.away_team_id),comp=competitionById(m.competition_id),gs=gamesFor(m.id),done=gs.filter(function(g){return g.status==='completed'}).length;
    return '<article class="meeting-card"><div class="meeting-label"><span>'+esc(comp?comp.name:'Súťaž')+'</span><span>'+esc(m.round_label||fmtDate(m.scheduled_at))+'</span></div><div class="meeting-score"><div><b>'+esc(home?home.name:'Domáci')+'</b><small>'+esc(home&&home.short_name||'')+'</small></div><strong>'+m.home_score+' : '+m.away_score+'</strong><div class="away"><b>'+esc(away?away.name:'Hostia')+'</b><small>'+esc(away&&away.short_name||'')+'</small></div></div><div class="meeting-foot"><span>Best of '+m.best_of+' · odohrané '+done+'/'+gs.length+'</span><span class="status '+esc(m.status)+'">'+esc(m.status)+'</span></div><button class="btn small" data-manage-meeting="'+m.id+'">Spravovať duely</button></article>';
  }).join('');
}

function renderRankingSelector(){
  $('rankingCompetition').innerHTML=state.competitions.length?state.competitions.map(function(c){return '<option value="'+c.id+'" '+(c.id===state.selectedCompetition?'selected':'')+'>'+esc(c.name)+'</option>'}).join(''):'<option value="">Bez súťaže</option>';
}

function renderRankings(){
  var comp=competitionById(state.selectedCompetition);
  if(!comp){$('standingsBody').innerHTML='<tr><td colspan="8">Bez dát.</td></tr>';$('playersBody').innerHTML='<tr><td colspan="8">Bez dát.</td></tr>';return}
  var tids=compTeamIds(comp.id),rows=new Map();
  tids.forEach(function(id){rows.set(id,{team:teamById(id),played:0,w:0,l:0,for:0,against:0,pts:0})});
  state.meetings.filter(function(m){return m.competition_id===comp.id&&m.status==='completed'}).forEach(function(m){
    var h=rows.get(m.home_team_id),a=rows.get(m.away_team_id);if(!h||!a)return;
    h.played++;a.played++;h.for+=m.home_score;h.against+=m.away_score;a.for+=m.away_score;a.against+=m.home_score;
    if(m.winner_team_id===m.home_team_id){h.w++;a.l++;h.pts+=comp.win_points;a.pts+=comp.loss_points}
    else if(m.winner_team_id===m.away_team_id){a.w++;h.l++;a.pts+=comp.win_points;h.pts+=comp.loss_points}
  });
  var standings=Array.from(rows.values()).sort(function(a,b){return b.pts-a.pts||((b.for-b.against)-(a.for-a.against))||b.for-a.for});
  $('standingsBody').innerHTML=standings.length?standings.map(function(r,i){var d=r.for-r.against;return '<tr><td>'+(i+1)+'</td><td>'+esc(r.team?r.team.name:'—')+'</td><td>'+r.played+'</td><td>'+r.w+'</td><td>'+r.l+'</td><td>'+r.for+':'+r.against+'</td><td>'+(d>0?'+':'')+d+'</td><td><b>'+r.pts+'</b></td></tr>'}).join(''):'<tr><td colspan="8">Bez dát.</td></tr>';

  var meetingIds=new Set(state.meetings.filter(function(m){return m.competition_id===comp.id}).map(function(m){return m.id})),pstats=new Map();
  function add(memberId,scoreFor,scoreAgainst,won){
    if(!memberId)return;var member=state.members.find(function(x){return x.id===memberId});if(!member)return;
    var r=pstats.get(memberId)||{member:member,played:0,w:0,l:0,for:0,against:0};r.played++;r.for+=scoreFor;r.against+=scoreAgainst;if(won)r.w++;else r.l++;pstats.set(memberId,r);
  }
  state.games.filter(function(g){return meetingIds.has(g.meeting_id)&&g.status==='completed'}).forEach(function(g){
    add(g.home_member_id,g.home_score,g.away_score,g.winner_member_id===g.home_member_id);
    add(g.away_member_id,g.away_score,g.home_score,g.winner_member_id===g.away_member_id);
  });
  var players=Array.from(pstats.values()).sort(function(a,b){return b.w-a.w||((b.for-b.against)-(a.for-a.against))||b.for-a.for});
  $('playersBody').innerHTML=players.length?players.map(function(r,i){var t=teamById(r.member.team_id);return '<tr><td>'+(i+1)+'</td><td>'+esc(r.member.display_name)+'</td><td>'+esc(t&&(t.short_name||t.name)||'—')+'</td><td>'+r.played+'</td><td>'+r.w+'</td><td>'+r.l+'</td><td>'+r.for+':'+r.against+'</td><td><b>'+(r.played?Math.round(r.w/r.played*100):0)+'%</b></td></tr>'}).join(''):'<tr><td colspan="8">Zatiaľ nie sú odohrané individuálne duely.</td></tr>';
}

function handleTeamAction(e){
  var b=e.target.closest('[data-add-member]');if(!b)return;var id=b.dataset.addMember,t=teamById(id);
  $('memberForm').reset();$('memberTeamId').value=id;$('memberModalTitle').textContent='Pridať hráča · '+(t?t.name:'Tím');openModal('memberModal');
}
function handleCompetitionAction(e){var b=e.target.closest('[data-comp-meeting]');if(b)openMeetingModal(b.dataset.compMeeting)}
function handleMeetingAction(e){var b=e.target.closest('[data-manage-meeting]');if(b)openDuelModal(b.dataset.manageMeeting)}

async function saveTeam(e){
  e.preventDefault();
  var payload={owner_id:state.session.user.id,name:$('teamName').value.trim(),short_name:$('teamShort').value.trim()||null,sport:$('teamSport').value.trim()||'Biliard',city:$('teamCity').value.trim()||null,country:$('teamCountry').value.trim()||null};
  var r=await cspAuth.client.from('teams').insert(payload);if(r.error){toast(r.error.message,true);return}
  closeModal('teamModal');toast('Tím vytvorený.');await loadAll();
}
async function saveMember(e){
  e.preventDefault();var teamId=$('memberTeamId').value;
  var payload={team_id:teamId,display_name:$('memberName').value.trim(),member_role:$('memberRole').value,sort_order:membersFor(teamId).length};
  var r=await cspAuth.client.from('team_members').insert(payload);if(r.error){toast(r.error.message,true);return}
  closeModal('memberModal');toast('Hráč pridaný do súpisky.');await loadAll();
}
function openCompetitionModal(){
  $('competitionForm').reset();$('competitionTeams').innerHTML=state.teams.map(function(t){return '<option value="'+t.id+'">'+esc(t.name)+'</option>'}).join('');openModal('competitionModal');
}
async function saveCompetition(e){
  e.preventDefault();var selected=Array.from($('competitionTeams').selectedOptions).map(function(o){return o.value});
  if(selected.length<2){toast('Vyber minimálne dva tímy.',true);return}
  var payload={owner_id:state.session.user.id,name:$('competitionName').value.trim(),sport:$('competitionSport').value.trim()||'Biliard',season_name:$('competitionSeason').value.trim()||null,default_best_of:Number($('competitionBestOf').value||5),default_discipline:$('competitionDiscipline').value.trim()||'9-ball',default_race_to:Number($('competitionRaceTo').value||5),status:'active'};
  var r=await cspAuth.client.from('team_competitions').insert(payload).select('id').single();if(r.error){toast(r.error.message,true);return}
  var links=selected.map(function(team_id){return {competition_id:r.data.id,team_id:team_id}});
  var lr=await cspAuth.client.from('team_competition_teams').insert(links);
  if(lr.error){await cspAuth.client.from('team_competitions').delete().eq('id',r.data.id);toast(lr.error.message,true);return}
  closeModal('competitionModal');toast('Tímová súťaž vytvorená.');await loadAll();
}
function openMeetingModal(compId){
  $('meetingForm').reset();$('meetingCompetition').innerHTML=state.competitions.map(function(c){return '<option value="'+c.id+'">'+esc(c.name)+'</option>'}).join('');
  $('meetingCompetition').value=compId||((state.competitions[0]&&state.competitions[0].id)||'');syncMeetingTeams();openModal('meetingModal');
}
function syncMeetingTeams(){
  var compId=$('meetingCompetition').value,ids=compTeamIds(compId),opts=ids.map(teamById).filter(Boolean).map(function(t){return '<option value="'+t.id+'">'+esc(t.name)+'</option>'}).join('');
  $('meetingHome').innerHTML=opts;$('meetingAway').innerHTML=opts;if(ids.length>1)$('meetingAway').value=ids[1];
  var c=competitionById(compId);if(c)$('meetingBestOf').value=c.default_best_of;
}
async function saveMeeting(e){
  e.preventDefault();if($('meetingHome').value===$('meetingAway').value){toast('Domáci a hostia musia byť rozdielne tímy.',true);return}
  var local=$('meetingDate').value,payload={competition_id:$('meetingCompetition').value,round_label:$('meetingRound').value.trim()||null,scheduled_at:local?new Date(local).toISOString():null,home_team_id:$('meetingHome').value,away_team_id:$('meetingAway').value,best_of:Number($('meetingBestOf').value||5)};
  var r=await cspAuth.client.from('team_meetings').insert(payload);if(r.error){toast(r.error.message,true);return}
  closeModal('meetingModal');toast('Stretnutie vytvorené aj s duelmi.');await loadAll();
}
function openDuelModal(meetingId){
  state.editingMeeting=meetingId;var m=state.meetings.find(function(x){return x.id===meetingId}),home=teamById(m.home_team_id),away=teamById(m.away_team_id);
  $('duelModalTitle').textContent=(home?home.name:'Domáci')+' vs '+(away?away.name:'Hostia');renderDuelRows();openModal('duelModal');
}
function renderDuelRows(){
  var m=state.meetings.find(function(x){return x.id===state.editingMeeting});if(!m)return;
  var hm=membersFor(m.home_team_id),am=membersFor(m.away_team_id);
  $('duelList').innerHTML=gamesFor(m.id).map(function(g){
    var ho=hm.map(function(x){return '<option value="'+x.id+'" '+(x.id===g.home_member_id?'selected':'')+'>'+esc(x.display_name)+'</option>'}).join('');
    var ao=am.map(function(x){return '<option value="'+x.id+'" '+(x.id===g.away_member_id?'selected':'')+'>'+esc(x.display_name)+'</option>'}).join('');
    return '<div class="duel-row" data-game="'+g.id+'"><div class="duel-no">#'+g.slot_no+'</div><select data-field="home_member_id"><option value="">Domáci hráč</option>'+ho+'</select><input data-field="home_score" type="number" min="0" value="'+g.home_score+'"><div class="duel-mid"><input data-field="discipline" value="'+esc(g.discipline)+'"><small>Race to</small><input data-field="race_to" type="number" min="1" value="'+g.race_to+'"></div><input data-field="away_score" type="number" min="0" value="'+g.away_score+'"><select data-field="away_member_id"><option value="">Hosťujúci hráč</option>'+ao+'</select><div class="duel-actions"><button class="btn small ghost" data-open-team-scoreboard="'+g.id+'">Scoreboard</button><button class="btn small '+(g.status==='completed'?'done':'')+'" data-save-game="'+g.id+'">'+(g.status==='completed'?'Uložiť ✓':'Uložiť výsledok')+'</button></div></div>';
  }).join('');
}
async function handleDuelAction(e){
  var scoreboardBtn=e.target.closest('[data-open-team-scoreboard]');
  var saveBtn=e.target.closest('[data-save-game]');
  var trigger=scoreboardBtn||saveBtn;
  if(!trigger)return;
  var id=scoreboardBtn?scoreboardBtn.dataset.openTeamScoreboard:saveBtn.dataset.saveGame;
  var row=e.target.closest('[data-game]');
  var field=function(name){return row.querySelector('[data-field="'+name+'"]').value};
  var common={
    home_member_id:field('home_member_id')||null,
    away_member_id:field('away_member_id')||null,
    discipline:field('discipline').trim()||'9-ball',
    race_to:Number(field('race_to')||1)
  };
  if(scoreboardBtn){
    if(!common.home_member_id||!common.away_member_id){toast('Najprv vyber oboch hráčov.',true);return}
    scoreboardBtn.disabled=true;scoreboardBtn.textContent='Otváram…';
    var setup=await cspAuth.client.from('team_match_games').update(common).eq('id',id);
    if(setup.error){scoreboardBtn.disabled=false;scoreboardBtn.textContent='Scoreboard';toast(setup.error.message,true);return}
    location.href='/scoreboard-te/?team_game_id='+encodeURIComponent(id)+'&smart=1';
    return;
  }
  var payload=Object.assign({},common,{home_score:Number(field('home_score')||0),away_score:Number(field('away_score')||0),status:'completed'});
  var r=await cspAuth.client.from('team_match_games').update(payload).eq('id',id);if(r.error){toast(r.error.message,true);return}
  toast('Výsledok duelu uložený.');await loadAll();if(state.editingMeeting)renderDuelRows();
}
init();
})();
