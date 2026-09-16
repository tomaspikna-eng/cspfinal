/* Connect Sports Pro — card tournament workflow improvements. */
(function(global){
  'use strict';
  const db=global.cspAuth?.client;
  if(!db)return;
  const path=global.location.pathname.replace(/\/+$/,'')||'/';
  const isGenerator=path==='/generator-stolov';
  const isTournament=path==='/turnament';
  if(!isGenerator&&!isTournament)return;

  let cachedTournamentId='';
  let cachedTournament=null;
  let latestCardState=null;
  let timer=null;

  function tournamentId(){
    const p=new URLSearchParams(global.location.search);
    return p.get('t')||p.get('tournament_id')||p.get('id')||'';
  }
  function isCards(row){
    return !!row&&(String(row.format||'').toLowerCase()==='karty'||['karty','cards','card'].includes(String(row.sport||'').trim().toLowerCase()));
  }
  function fairTableCount(count,preferred,finalCount=4){
    count=Number(count)||0;preferred=Math.max(2,Math.min(8,Number(preferred)||4));
    if(count<=0)return 0;if(count<=finalCount)return 1;
    const minTables=Math.max(1,Math.ceil(count/preferred));
    const maxTables=Math.min(Math.max(minTables,Math.floor(count/2)),minTables+1);
    let best=null,bestImbalance=999,bestDistance=999;
    for(let tables=minTables;tables<=maxTables;tables++){
      const minSize=Math.floor(count/tables),maxSize=Math.ceil(count/tables);
      if(minSize<Math.max(2,preferred-1)||maxSize>preferred)continue;
      const imbalance=maxSize-minSize,distance=Math.abs(count/tables-preferred);
      if(best===null||imbalance<bestImbalance||(imbalance===bestImbalance&&distance<bestDistance)){
        best=tables;bestImbalance=imbalance;bestDistance=distance;
      }
    }
    return best??minTables;
  }
  function distribution(count,preferred){
    const tables=fairTableCount(count,preferred,4);if(!tables)return {tables:0,sizes:[]};
    const base=Math.floor(count/tables),extra=count%tables;
    return {tables,sizes:Array.from({length:tables},(_,i)=>base+(i<extra?1:0))};
  }
  async function loadTournament(){
    const id=tournamentId();
    if(!id){cachedTournamentId='';cachedTournament=null;latestCardState=null;return null}
    if(id===cachedTournamentId&&cachedTournament)return cachedTournament;
    cachedTournamentId=id;
    const {data,error}=await db.from('tournaments').select('id,owner_id,name,sport,discipline,format,date,source_event_id').eq('id',id).maybeSingle();
    if(error||!data){cachedTournament=null;return null}
    cachedTournament=data;
    if(isCards(data)){
      const state=await db.rpc('get_card_tournament_state',{p_tournament_id:id});
      latestCardState=state.error?null:state.data;
    }else latestCardState=null;
    return data;
  }
  function conversionUrl(mode,id){return `/turnament-konverzia/?id=${encodeURIComponent(id)}&mode=${mode}`}
  function makeLink(text,href,className='btn btn-secondary'){
    const a=document.createElement('a');a.textContent=text;a.href=href;a.className=className;return a;
  }

  function enhanceGeneratorActions(row){
    const id=row?.id;if(!id)return;
    const actions=document.querySelector('.hero-actions');if(!actions)return;
    const series=document.getElementById('seriesBtn');
    if(series){series.textContent='Vytvoriť sériu';series.href=conversionUrl('series',id)}
    if(!document.getElementById('cspCreateLeagueFromTournament')){
      const league=makeLink('Vytvoriť ligu',conversionUrl('league',id));
      league.id='cspCreateLeagueFromTournament';actions.appendChild(league);
    }
  }
  function setupNamesCount(){
    const box=document.getElementById('playerNames');if(!box)return 0;
    return new Set(box.value.split(/\r?\n/).map(x=>x.trim()).filter(Boolean).map(x=>x.toLocaleLowerCase())).size;
  }
  function applyFairSetup(){
    if(!isGenerator)return;
    const names=document.getElementById('playerNames'),per=document.getElementById('playersPerTable'),tableCount=document.getElementById('tableCount'),suggested=document.getElementById('suggestedTables');
    if(!names||!per||!tableCount||!suggested||per.disabled)return;
    const count=setupNamesCount(),tables=fairTableCount(count,Number(per.value),4);
    tableCount.value=tables||'';suggested.textContent=String(tables||0);
  }
  function bindFairSetup(){
    const names=document.getElementById('playerNames'),per=document.getElementById('playersPerTable');
    if(names&&!names.dataset.cspFairBound){names.dataset.cspFairBound='1';names.addEventListener('input',()=>setTimeout(applyFairSetup,0))}
    if(per&&!per.dataset.cspFairBound){per.dataset.cspFairBound='1';per.addEventListener('change',()=>setTimeout(applyFairSetup,0))}
    applyFairSetup();
  }
  function currentSurvivors(){
    const state=latestCardState;if(!state?.settings)return 0;
    const number=Number(state.settings.current_round_number);
    const round=(state.rounds||[]).find(r=>Number(r.number)===number);
    return (round?.tables||[]).flatMap(t=>t.players||[]).filter(p=>p.outcome==='active').length;
  }
  function updateNextRoundHint(control){
    const select=control.querySelector('select'),hint=control.querySelector('.csp-fair-hint');
    const count=currentSurvivors(),preferred=Number(select?.value||4);
    if(!hint)return;
    if(count<=4){hint.textContent=`${count} hráči · finálový stôl`;return}
    const d=distribution(count,preferred);
    hint.textContent=`Návrh: ${d.tables} stolov · ${d.sizes.join(' + ')} hráči`;
  }
  function enhanceNextRoundButton(){
    if(!isGenerator||!latestCardState?.settings)return;
    const actions=[...document.querySelectorAll('.round-actions')];
    for(const action of actions){
      const old=[...action.querySelectorAll('button')].find(b=>/Vygenerovať (ďalšie kolo|finálový stôl)/i.test(b.textContent||''));
      if(!old||old.dataset.cspConfigured==='1')continue;
      const clone=old.cloneNode(true);clone.dataset.cspConfigured='1';old.replaceWith(clone);
      const control=document.createElement('div');control.className='csp-next-round-control';
      const final=currentSurvivors()<=4;
      control.innerHTML=final?`<span class="csp-fair-hint"></span>`:`<label>Hráčov na stole v ďalšom kole <select>${[2,3,4,5].map(n=>`<option value="${n}" ${Number(latestCardState.settings.players_per_table)===n?'selected':''}>${n}</option>`).join('')}</select></label><span class="csp-fair-hint"></span>`;
      action.insertBefore(control,clone);
      const select=control.querySelector('select');if(select)select.addEventListener('change',()=>updateNextRoundHint(control));
      updateNextRoundHint(control);
      clone.addEventListener('click',async()=>{
        if(clone.disabled)return;
        clone.disabled=true;const preferred=Number(select?.value||latestCardState.settings.players_per_table||4);
        const result=await db.rpc('advance_card_round_configured',{p_tournament_id:tournamentId(),p_players_per_table:preferred});
        if(result.error){clone.disabled=false;global.alert(result.error.message);return}
        global.location.reload();
      });
    }
  }
  async function refreshGeneratorState(){
    if(!isGenerator||!cachedTournament||!isCards(cachedTournament))return;
    const result=await db.rpc('get_card_tournament_state',{p_tournament_id:cachedTournament.id});
    if(!result.error)latestCardState=result.data;
    bindFairSetup();enhanceNextRoundButton();
  }

  function selectedWizardIsCards(){
    return [...document.querySelectorAll('.pill.sel,.pill.selected,.seg.active,.chip.active')].some(el=>String(el.textContent||'').trim().toLowerCase()==='karty');
  }
  function hideRaceControls(cardActive){
    const raceInput=document.getElementById('wRaceTo');
    const hideWizard=cardActive||selectedWizardIsCards();
    if(raceInput){const field=raceInput.closest('.field');if(field)field.style.display=hideWizard?'none':''}
    document.querySelectorAll('.round-race-control').forEach(el=>{el.style.display=cardActive?'none':''});
  }
  function injectTournamentConversionBar(row){
    const existing=document.getElementById('cspCardConvertBar');
    if(!row||!isCards(row)){existing?.remove();return}
    if(existing){existing.querySelector('[data-mode="league"]').href=conversionUrl('league',row.id);existing.querySelector('[data-mode="series"]').href=conversionUrl('series',row.id);return}
    const wrap=document.querySelector('#app .wrap');if(!wrap)return;
    const bar=document.createElement('div');bar.id='cspCardConvertBar';bar.className='csp-card-convert-bar';
    bar.innerHTML=`<strong>Kartový turnaj</strong><span>Prepojiť turnaj ďalej:</span><a data-mode="league" href="${conversionUrl('league',row.id)}">Vytvoriť ligu</a><a data-mode="series" href="${conversionUrl('series',row.id)}">Vytvoriť sériu</a>`;
    wrap.insertBefore(bar,wrap.firstChild);
  }
  function injectStyles(){
    if(document.getElementById('cspCardEnhancementStyle'))return;
    const style=document.createElement('style');style.id='cspCardEnhancementStyle';style.textContent=`
      .csp-next-round-control{display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin-left:auto}.csp-next-round-control label{margin:0;display:flex;align-items:center;gap:8px;font-size:.85rem}.csp-next-round-control select{width:auto;min-width:70px;min-height:42px;padding:0 10px}.csp-fair-hint{color:rgba(255,255,255,.7);font-size:.82rem;font-weight:700}.csp-card-convert-bar{display:flex;align-items:center;gap:10px;flex-wrap:wrap;margin:0 0 14px;padding:11px 13px;border:1px solid rgba(212,168,67,.28);background:rgba(212,168,67,.07);border-radius:10px;font-size:.78rem}.csp-card-convert-bar strong{color:#d4a843}.csp-card-convert-bar span{color:#9ca0a8}.csp-card-convert-bar a{color:#fff;text-decoration:none;border:1px solid rgba(255,255,255,.12);border-radius:7px;padding:7px 9px;font-weight:800}.csp-card-convert-bar a:hover{border-color:rgba(212,168,67,.5)}
    `;document.head.appendChild(style);
  }
  async function enhance(){
    injectStyles();
    const row=await loadTournament();
    if(isGenerator){if(row&&isCards(row)){enhanceGeneratorActions(row);bindFairSetup();await refreshGeneratorState()}}
    if(isTournament){hideRaceControls(isCards(row));injectTournamentConversionBar(row)}
  }
  function schedule(){clearTimeout(timer);timer=setTimeout(()=>enhance().catch(err=>console.error('[csp-card-enhancements]',err)),80)}
  new MutationObserver(schedule).observe(document.documentElement,{subtree:true,childList:true,attributes:true,attributeFilter:['class']});
  global.addEventListener('popstate',schedule);
  document.addEventListener('change',event=>{if(isTournament&&event.target.closest?.('.pill,.seg,.chip'))schedule()});
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',schedule);else schedule();
})(window);
