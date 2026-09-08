(function(){
  'use strict';

  const $=id=>document.getElementById(id);
  const playerNamesEl=$('playerNames');
  const playersPerTableEl=$('playersPerTable');
  const tableCountEl=$('tableCount');
  const playerCountEl=$('playerCount');
  const suggestedTablesEl=$('suggestedTables');
  const duplicatesBox=$('duplicatesBox');
  const tablesOutput=$('tablesOutput');
  const statusMessage=$('statusMessage');
  const generateBtn=$('generateBtn');
  const clearBtn=$('clearBtn');
  const syncLine=$('syncLine');
  const syncText=$('syncText');
  const params=new URLSearchParams(location.search);
  const tournamentId=params.get('t')||params.get('tournament_id')||params.get('id')||'';
  const FINAL_PLAYER_COUNT=4;

  let state=null;
  let session=null;
  let busy=false;
  let refreshTimer=null;
  const finalPlacements=new Map();

  function normalizeName(value){
    return String(value||'').trim().toLocaleLowerCase('sk-SK').replace(/\s+/g,' ');
  }
  function duplicates(players){
    const counts=new Map();
    for(const player of players||[]){
      const key=normalizeName(player.name);
      if(key)counts.set(key,(counts.get(key)||0)+1);
    }
    return [...counts.entries()].filter(([,count])=>count>1).map(([name])=>name);
  }
  function suggestTableCount(playerCount,playersPerTable){
    if(!playerCount||!playersPerTable)return 0;
    if(playerCount<=FINAL_PLAYER_COUNT+1)return 1;
    return Math.max(1,Math.min(Math.floor(playerCount/2),Math.ceil(playerCount/playersPerTable)));
  }
  function message(text,type=''){
    statusMessage.textContent=text||'';
    statusMessage.className=text?'notice show'+(type?' '+type:''):'notice';
  }
  function sync(ok,text){
    syncLine.classList.toggle('offline',!ok);
    syncText.textContent=text;
  }
  function errorText(error){
    const raw=String(error?.message||error||'Neznáma chyba');
    const labels={
      CARD_TOURNAMENT_NOT_FOUND:'Kartový turnaj sa nenašiel.',
      CARD_TOURNAMENT_NOT_FOUND_OR_FORBIDDEN:'Turnaj sa nenašiel alebo ho nemôžeš spravovať.',
      CARD_TOURNAMENT_ACCESS_DENIED:'Tento turnaj môže spravovať iba jeho organizátor.',
      NOT_A_CARD_TOURNAMENT:'Tento turnaj nie je nastavený ako kartový.',
      CARD_TOURNAMENT_ALREADY_STARTED:'Kartový turnaj už bol spustený.',
      CARD_TOURNAMENT_ALREADY_COMPLETED:'Ukončený turnaj už nie je možné meniť.',
      CARD_TOURNAMENT_REQUIRES_AT_LEAST_FOUR_PLAYERS:'Kartový turnaj potrebuje najmenej štyroch hráčov.',
      CARD_TOURNAMENT_REQUIRES_PLAYER_IDENTITIES:'Niektorému hráčovi chýba CSP identita. Otvor nastavenia turnaja a zoznam znovu ulož.',
      MARK_AT_LEAST_ONE_ELIMINATED_PLAYER:'Pred ukončením stola označ aspoň jedného vypadávajúceho.',
      AT_LEAST_ONE_PLAYER_MUST_ADVANCE_FROM_TABLE:'Z každého stola musí postúpiť aspoň jeden hráč.',
      ALL_CARD_TABLES_MUST_BE_COMPLETED:'Najskôr ukonči všetky stoly aktuálneho kola.',
      TOO_FEW_PLAYERS_FOR_FINAL:'Po vyradení musia zostať aspoň štyria hráči.',
      FINAL_POSITIONS_MUST_BE_UNIQUE:'Každý finalista musí mať iné umiestnenie.',
      ALL_FINALISTS_REQUIRE_PLACEMENT:'Nastav umiestnenie všetkým finalistom.',
      COMPLETED_CARD_TOURNAMENT_IS_LOCKED:'Ukončený turnaj je uzamknutý.'
    };
    const key=Object.keys(labels).find(item=>raw.includes(item));
    return key?labels[key]:(window.cspAuth?.formatError?.(error)||raw);
  }
  function currentRound(){
    const rounds=state?.rounds||[];
    return rounds[rounds.length-1]||null;
  }
  function activePlayers(round){
    return (round?.tables||[]).flatMap(table=>table.players||[]).filter(player=>player.outcome!=='eliminated');
  }
  function eliminatedCount(round){
    return (round?.tables||[]).flatMap(table=>table.players||[]).filter(player=>player.outcome==='eliminated').length;
  }
  function allTablesClosed(round){
    return !!round?.tables?.length&&round.tables.every(table=>table.status==='completed');
  }
  function setBusy(value){
    busy=!!value;
    document.querySelector('.card')?.classList.toggle('busy',busy);
  }
  function updateSetup(){
    const players=state?.players||[];
    const perTable=Math.max(2,Number(playersPerTableEl.value)||4);
    const suggested=suggestTableCount(players.length,perTable);
    const repeated=duplicates(players);
    playerNamesEl.value=players.map(player=>player.name).join('\n');
    playerCountEl.textContent=String(players.length);
    suggestedTablesEl.textContent=String(suggested);
    if(!tableCountEl.dataset.touched)tableCountEl.value=String(suggested||1);
    duplicatesBox.classList.toggle('show',repeated.length>0);
    duplicatesBox.textContent=repeated.length?'Duplicitné mená v turnaji: '+repeated.join(', '):'';
    generateBtn.disabled=busy||!!state?.settings||players.length<FINAL_PLAYER_COUNT||repeated.length>0;
  }
  function updateLinks(){
    $('backTournamentBtn').href=tournamentId?`/turnament/?id=${encodeURIComponent(tournamentId)}`:'/turnament/';
    $('projectorBtn').href=tournamentId?`/displayview/?id=${encodeURIComponent(tournamentId)}`:'/displayview/';
    const tournament=state?.tournament||{};
    const seriesBtn=$('seriesBtn');
    if(tournament.series_id){
      seriesBtn.textContent='Celkové poradie sezóny';
      seriesBtn.href=`/seria/?id=${encodeURIComponent(tournament.series_id)}`;
    }else{
      seriesBtn.textContent='Vytvoriť sezónu';
      const seasonUrl=new URL('/udalost/',location.origin);
      seasonUrl.searchParams.set('sport','Karty');
      seasonUrl.searchParams.set('discipline',tournament.discipline||'');
      seasonUrl.searchParams.set('series','1');
      seriesBtn.href=seasonUrl.pathname+seasonUrl.search;
    }
  }
  function setupContext(){
    const tournament=state?.tournament||{};
    const context=$('tournamentContext');
    context.style.display='block';
    $('tournamentContextName').textContent=tournament.name||'Kartový turnaj';
    $('tournamentContextDiscipline').textContent=tournament.discipline?' · '+tournament.discipline:'';
    document.querySelector('.hero h1').textContent=tournament.name||'Kartový turnaj';
    document.title=(tournament.name||'Kartový turnaj')+' | Connect Sports Pro';
  }
  function setSetupLocked(locked){
    playersPerTableEl.disabled=locked;
    tableCountEl.disabled=locked;
    generateBtn.textContent=state?.settings?.status==='completed'?'Turnaj je ukončený':locked?'Turnaj prebieha':'Vygenerovať prvé kolo';
    clearBtn.textContent=locked?'Začať turnaj odznova':'Otvoriť nastavenia hráčov';
    clearBtn.disabled=state?.settings?.status==='completed'||busy;
  }
  function playerRow(round,table,player,interactive){
    const item=document.createElement('div');
    item.className='player-item'+(player.outcome==='eliminated'?' eliminated':'');
    const name=document.createElement('span');
    name.textContent=player.name;
    item.appendChild(name);
    if(round.type!=='final'){
      const label=document.createElement('label');
      label.className='elimination-label';
      const checkbox=document.createElement('input');
      checkbox.type='checkbox';
      checkbox.checked=player.outcome==='eliminated';
      checkbox.disabled=!interactive||table.status==='completed'||busy;
      checkbox.setAttribute('aria-label',`Vypadáva: ${player.name}`);
      checkbox.addEventListener('change',()=>setEliminated(table.id,player.id,checkbox.checked));
      const text=document.createElement('span');
      text.textContent=player.outcome==='eliminated'?'Vypadáva':'Postupuje';
      label.append(checkbox,text);
      item.appendChild(label);
    }
    return item;
  }
  function renderQualification(round,container,isCurrent){
    const grid=document.createElement('div');
    grid.className='round-tables';
    for(const table of round.tables||[]){
      const card=document.createElement('div');
      card.className='table-card';
      const head=document.createElement('div');
      head.className='table-card-head';
      const title=document.createElement('h4');title.textContent=table.name;
      const badge=document.createElement('span');
      badge.className='status-badge'+(table.status==='completed'?' closed':'');
      badge.textContent=table.status==='completed'?'Ukončený':'Prebieha';
      head.append(title,badge);card.appendChild(head);
      const list=document.createElement('div');list.className='player-list';
      for(const player of table.players||[])list.appendChild(playerRow(round,table,player,isCurrent));
      card.appendChild(list);
      if(isCurrent){
        const actions=document.createElement('div');actions.className='table-actions';
        const button=document.createElement('button');button.type='button';
        button.className='btn '+(table.status==='completed'?'btn-secondary':'btn-primary');
        button.textContent=table.status==='completed'?'Znovu otvoriť stôl':'Ukončiť stôl';
        button.disabled=busy;
        button.addEventListener('click',()=>setTableStatus(table.id,table.status==='completed'?'open':'completed'));
        actions.appendChild(button);card.appendChild(actions);
      }
      grid.appendChild(card);
    }
    container.appendChild(grid);
    const actions=document.createElement('div');actions.className='round-actions';
    const survivors=activePlayers(round);
    const summary=document.createElement('div');summary.className='round-summary';
    summary.innerHTML=`Vypadávajúci: <strong>${eliminatedCount(round)}</strong> · Postupuje: <strong>${survivors.length}</strong> · Finále: <strong>${FINAL_PLAYER_COUNT}</strong>`;
    actions.appendChild(summary);
    if(isCurrent){
      const next=document.createElement('button');next.type='button';next.className='btn btn-primary';
      next.textContent=survivors.length===FINAL_PLAYER_COUNT?'Vygenerovať finálový stôl':'Vygenerovať ďalšie kolo';
      next.disabled=busy||!allTablesClosed(round)||survivors.length<FINAL_PLAYER_COUNT||survivors.length===((round.tables||[]).flatMap(table=>table.players||[]).length);
      next.addEventListener('click',advanceRound);actions.appendChild(next);
    }
    container.appendChild(actions);
  }
  function renderFinal(round,container,isCurrent){
    const table=round.tables?.[0];
    if(!table)return;
    const card=document.createElement('div');card.className='table-card';
    const head=document.createElement('div');head.className='table-card-head';
    const title=document.createElement('h4');title.textContent='Finálový stôl';
    const badge=document.createElement('span');badge.className='status-badge closed';badge.textContent=`${table.players.length} hráči`;
    head.append(title,badge);card.appendChild(head);
    const ranking=document.createElement('div');ranking.className='final-ranking';
    for(const player of table.players||[]){
      if(player.final_position)finalPlacements.set(player.id,Number(player.final_position));
      const row=document.createElement('div');row.className='final-ranking-row';
      const name=document.createElement('strong');name.textContent=player.name;
      const select=document.createElement('select');
      select.disabled=!isCurrent||state.settings?.status==='completed'||busy;
      select.setAttribute('aria-label',`Umiestnenie: ${player.name}`);
      select.innerHTML='<option value="">Umiestnenie</option>'+table.players.map((_,index)=>`<option value="${index+1}">${index+1}. miesto</option>`).join('');
      select.value=finalPlacements.get(player.id)||'';
      select.addEventListener('change',()=>{
        if(select.value)finalPlacements.set(player.id,Number(select.value));else finalPlacements.delete(player.id);
        renderTournament();
      });
      row.append(name,select);ranking.appendChild(row);
    }
    card.appendChild(ranking);container.appendChild(card);
    if(isCurrent&&state.settings?.status!=='completed'){
      const actions=document.createElement('div');actions.className='round-actions';
      const summary=document.createElement('div');summary.className='round-summary';
      summary.textContent='Každému finalistovi nastav jedinečné umiestnenie.';
      const finish=document.createElement('button');finish.type='button';finish.className='btn btn-primary';
      finish.textContent='Ukončiť turnaj a zverejniť výsledky';
      finish.disabled=busy||!finalRankingValid(table.players);
      finish.addEventListener('click',completeTournament);
      actions.append(summary,finish);container.appendChild(actions);
    }
  }
  function finalRankingValid(players){
    const values=(players||[]).map(player=>Number(finalPlacements.get(player.id)||0));
    return values.length===FINAL_PLAYER_COUNT&&values.every(value=>value>=1&&value<=FINAL_PLAYER_COUNT)&&new Set(values).size===values.length;
  }
  function renderTournament(){
    tablesOutput.innerHTML='';
    updateSetup();updateLinks();setupContext();
    const rounds=state?.rounds||[];
    setSetupLocked(!!state?.settings);
    for(const [index,round] of rounds.entries()){
      const isCurrent=index===rounds.length-1&&state.settings?.status==='in_progress';
      const block=document.createElement('section');block.className='round-block'+(isCurrent?' current':'');
      const header=document.createElement('div');header.className='round-header';
      const heading=document.createElement('div');
      const title=document.createElement('h3');title.textContent=round.type==='final'?'Finále':`Kolo ${round.number}`;
      const meta=document.createElement('div');meta.className='round-meta';
      const playerCount=(round.tables||[]).flatMap(table=>table.players||[]).length;
      meta.textContent=round.type==='final'?`Jeden stôl · ${playerCount} hráči`:`${playerCount} hráčov · ${round.tables.length} ${round.tables.length===1?'stôl':'stoly'}`;
      heading.append(title,meta);header.appendChild(heading);block.appendChild(header);
      if(round.type==='final')renderFinal(round,block,isCurrent);else renderQualification(round,block,isCurrent);
      tablesOutput.appendChild(block);
    }
    if(state?.settings?.status==='completed'){
      const final=currentRound();
      const winner=final?.tables?.[0]?.players?.find(player=>Number(player.final_position)===1);
      const banner=document.createElement('div');banner.className='winner-banner';
      banner.innerHTML='Turnaj bol ukončený a výsledky sú započítané.<br>Víťaz: ';
      const strong=document.createElement('strong');strong.textContent=winner?.name||'—';banner.appendChild(strong);
      tablesOutput.prepend(banner);
      message(state.tournament?.series_id?'Výsledky boli započítané do celkového poradia sezóny.':'Výsledky turnaja boli uložené.','success');
    }
  }
  async function loadState(silent=false){
    if(!tournamentId)throw new Error('V odkaze chýba ID turnaja.');
    const {data,error}=await cspAuth.client.rpc('get_card_tournament_state',{p_tournament_id:tournamentId});
    if(error)throw error;
    state=data;
    renderTournament();
    if(!silent)sync(true,'Turnaj je synchronizovaný s CSP');
  }
  async function runRpc(name,args,successText){
    if(busy)return;
    setBusy(true);message('');
    try{
      const {data,error}=await cspAuth.client.rpc(name,args);
      if(error)throw error;
      state=data;
      renderTournament();
      sync(true,'Zmeny sú uložené na všetkých zariadeniach');
      if(successText)message(successText,'success');
    }catch(error){
      console.error('[generator-stolov]',name,error);
      message(errorText(error),'error');
      sync(false,'Posledná zmena sa neuložila');
      await loadState(true).catch(()=>{});
    }finally{setBusy(false);renderTournament();}
  }
  function startTournament(){
    const repeated=duplicates(state?.players||[]);
    if(repeated.length){message('Najskôr odstráň duplicitných hráčov v nastaveniach turnaja.','error');return;}
    const perTable=Math.max(2,Math.min(8,Number(playersPerTableEl.value)||4));
    const maxTables=Math.max(1,Math.floor((state?.players?.length||0)/2));
    const tableCount=Math.max(1,Math.min(maxTables,Number(tableCountEl.value)||1));
    runRpc('start_card_tournament',{
      p_tournament_id:tournamentId,p_players_per_table:perTable,p_table_count:tableCount
    },'Prvé kolo bolo vygenerované.');
  }
  function setEliminated(tableId,playerId,eliminated){
    runRpc('set_card_player_eliminated',{
      p_table_id:tableId,p_tournament_player_id:playerId,p_eliminated:eliminated
    });
  }
  function setTableStatus(tableId,status){
    runRpc('set_card_table_status',{p_table_id:tableId,p_status:status});
  }
  function advanceRound(){
    runRpc('advance_card_round',{p_tournament_id:tournamentId},'Ďalšie kolo bolo vygenerované.');
  }
  function completeTournament(){
    const players=currentRound()?.tables?.[0]?.players||[];
    if(!finalRankingValid(players)){message('Vo finále nastav každému hráčovi jedinečné umiestnenie.','error');return;}
    const placements=players.map(player=>({
      tournament_player_id:player.id,final_position:Number(finalPlacements.get(player.id))
    }));
    runRpc('complete_card_tournament',{
      p_tournament_id:tournamentId,p_placements:placements
    });
  }
  async function resetTournament(){
    if(!state?.settings){location.href=`/turnament/?id=${encodeURIComponent(tournamentId)}&mode=settings`;return;}
    if(!confirm('Naozaj chceš zmazať všetky kartové kolá a začať turnaj odznova?'))return;
    finalPlacements.clear();
    await runRpc('reset_card_tournament',{p_tournament_id:tournamentId},'Turnaj bol vrátený do nastavenia.');
  }

  playersPerTableEl.addEventListener('change',()=>{tableCountEl.dataset.touched='';updateSetup();});
  tableCountEl.addEventListener('input',()=>{tableCountEl.dataset.touched='1';});
  generateBtn.addEventListener('click',startTournament);
  clearBtn.addEventListener('click',resetTournament);

  (async function init(){
    try{
      if(!tournamentId)throw new Error('V odkaze chýba ID kartového turnaja.');
      const {data:{session:activeSession}}=await cspAuth.withTimeout(cspAuth.getSession(),8000,'getSession');
      session=activeSession;
      if(!session){location.href='/login/?next='+encodeURIComponent(location.pathname+location.search);return;}
      await loadState();
      refreshTimer=setInterval(()=>{
        if(!busy&&state?.settings?.status==='in_progress')loadState(true).catch(error=>sync(false,errorText(error)));
      },3000);
      document.addEventListener('visibilitychange',()=>{
        if(!document.hidden&&!busy)loadState(true).catch(()=>{});
      });
    }catch(error){
      console.error('[generator-stolov] init',error);
      message(errorText(error),'error');sync(false,'Turnaj sa nepodarilo načítať');
      generateBtn.disabled=true;clearBtn.disabled=true;
    }
  })();
})();
