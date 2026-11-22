(function(){
  if(window.__cspMultiStageTournaments20261122)return;
  window.__cspMultiStageTournaments20261122=true;

  function comboFormat(value){return value==='rr_sko'||value==='rr_dko';}
  function wizardMulti(){return comboFormat(wiz&&wiz.format)&&wiz.multiStage===true;}
  function clampDirect(value,total){
    total=Number(total==null?(wiz&&wiz.players?wiz.players.length:0):total)||0;
    return Math.max(0,Math.min(Math.max(0,total-2),Number(value)||0));
  }
  function wizardQualificationPlayers(){
    var players=Array.isArray(wiz&&wiz.players)?wiz.players:[];
    return wizardMulti()?players.slice(clampDirect(wiz.directCount,players.length)):players;
  }
  function wizardQualifierCount(){
    var q=wizardQualificationPlayers();
    return comboQualifierCount(q.length,Math.max(1,Number(wiz.groups)||1),Math.max(1,Number(wiz.advance)||1));
  }
  function wizardFinalCount(){
    return (wizardMulti()?clampDirect(wiz.directCount):0)+wizardQualifierCount();
  }
  function wizardFinalBracketSize(){return TM.nextPow2(Math.max(2,wizardFinalCount()));}
  function assignmentLabel(mode){
    if(mode==='ordered')return 'Podľa výsledku kvalifikácie';
    if(mode==='manual')return 'Manuálne';
    return 'Náhodný žreb + manuálna úprava';
  }
  function tournamentMultiConfig(t){
    var cfg=t&&t.config&&typeof t.config.multi_stage==='object'?t.config.multi_stage:null;
    return cfg&&cfg.enabled===true?cfg:null;
  }
  function tournamentMulti(t){return !!(t&&comboFormat(t.format)&&tournamentMultiConfig(t));}
  function directCountFor(t){
    var cfg=tournamentMultiConfig(t);
    var players=Array.isArray(t&&t.players)?t.players:[];
    return cfg?Math.max(0,Math.min(players.length,Number(cfg.direct_count)||0)):0;
  }
  function sortedTournamentPlayers(t){
    return (Array.isArray(t&&t.players)?t.players:[]).slice().sort(function(a,b){
      return Number(a.seed||999999)-Number(b.seed||999999);
    });
  }
  function directPlayersFor(t){return sortedTournamentPlayers(t).slice(0,directCountFor(t));}
  function qualificationPlayersFor(t){return sortedTournamentPlayers(t).slice(directCountFor(t));}
  function playerKey(p){return String(p&&p.id?p.id:(p&&p.name?p.name:''));}
  function qualificationSourceLabel(row){
    if(!row)return '';
    return 'Skupina '+String(row.group||String.fromCharCode(65+Number(row.groupIndex||0)))+' · '+Number(row.rank||0)+'. miesto';
  }
  function finalTypeLabel(t){return t&&t.format==='rr_dko'?'Double KO':'Single KO';}

  var originalBlankWiz=blankWiz;
  blankWiz=function(){
    var out=originalBlankWiz();
    out.multiStage=false;
    out.directCount=0;
    out.qualifierAssignment='random';
    return out;
  };

  var originalWizardSnapshot=wizardSnapshot;
  wizardSnapshot=function(){
    var snap=originalWizardSnapshot();
    snap.multiStage=!!(comboFormat(snap.format)&&wiz.multiStage);
    snap.directCount=snap.multiStage?clampDirect(wiz.directCount,(wiz.players||[]).length):0;
    snap.qualifierAssignment=['ordered','random','manual'].indexOf(wiz.qualifierAssignment)>=0?wiz.qualifierAssignment:'random';
    return snap;
  };

  var originalCaptureWizardInputs=captureWizardInputs;
  captureWizardInputs=function(){
    originalCaptureWizardInputs();
    var d=document.getElementById('wDirectCount');
    var a=document.getElementById('wQualifierAssignment');
    if(d)wiz.directCount=clampDirect(d.value,(wiz.players||[]).length);
    if(a)wiz.qualifierAssignment=['ordered','random','manual'].indexOf(a.value)>=0?a.value:'random';
    if(wizardMulti())wiz.seedCount=clampDirect(wiz.directCount,(wiz.players||[]).length);
  };

  var originalInitWizard=initWizard;
  initWizard=function(existing){
    var enhanced=existing;
    if(existing){
      var cfg=existing.config&&typeof existing.config.multi_stage==='object'?existing.config.multi_stage:{};
      enhanced=Object.assign({},existing,{
        multiStage:existing.multiStage!=null?existing.multiStage:cfg.enabled===true,
        directCount:Number(existing.directCount!=null?existing.directCount:(cfg.direct_count||0)),
        qualifierAssignment:existing.qualifierAssignment||cfg.qualifier_assignment||'random'
      });
    }
    originalInitWizard(enhanced);
    wiz.multiStage=!!(comboFormat(wiz.format)&&wiz.multiStage);
    wiz.directCount=clampDirect(wiz.directCount,(wiz.players||[]).length);
    wiz.qualifierAssignment=['ordered','random','manual'].indexOf(wiz.qualifierAssignment)>=0?wiz.qualifierAssignment:'random';
    if(wizardMulti())wiz.seedCount=wiz.directCount;
  };

  window.setMultiStageEnabled=function(enabled){
    wiz.multiStage=!!enabled;
    if(!wiz.multiStage)wiz.directCount=0;
    wiz.directCount=clampDirect(wiz.directCount,(wiz.players||[]).length);
    if(wiz.multiStage)wiz.seedCount=wiz.directCount;
    renderWiz();
    flushWizardAutosave(false);
  };
  window.setMultiStageDirectCount=function(value){
    wiz.directCount=clampDirect(value,(wiz.players||[]).length);
    wiz.seedCount=wiz.directCount;
    var el=document.getElementById('wDirectCount');if(el)el.value=String(wiz.directCount);
    refreshGroupNote();
    renderMultiStageWizardDecorations();
    flushWizardAutosave(false);
  };
  window.setMultiStageAssignment=function(value){
    wiz.qualifierAssignment=['ordered','random','manual'].indexOf(value)>=0?value:'random';
    flushWizardAutosave(false);
  };

  function renderMultiStageWizardDecorations(){
    var panel=document.getElementById('wizPanel');
    if(!panel||!wizardMulti())return;
    wiz.directCount=clampDirect(wiz.directCount,(wiz.players||[]).length);
    wiz.seedCount=wiz.directCount;

    if(wiz.step===2){
      var groupSection=Array.prototype.slice.call(panel.querySelectorAll('.fmt-section')).find(function(el){
        return el.textContent.trim()==='Nastavenie skupín';
      });
      if(groupSection){
        groupSection.textContent='Nastavenie kvalifikácie';
        var wrap=document.createElement('div');
        wrap.id='multiStageWizardOptions';
        wrap.innerHTML=
          '<div class="fmt-section">Viacfázový turnaj</div>'+
          '<div class="row2">'+
            '<div class="field"><label>Priamo do finále</label>'+
              '<input type="number" id="wDirectCount" min="0" max="'+Math.max(0,(wiz.players||[]).length-2)+'" value="'+wiz.directCount+'" oninput="setMultiStageDirectCount(this.value)"/>'+
              '<div class="hint">Prvých '+wiz.directCount+' hráčov v zozname obíde kvalifikáciu.</div></div>'+
            '<div class="field"><label>Priradenie kvalifikantov</label>'+
              '<select id="wQualifierAssignment" onchange="setMultiStageAssignment(this.value)">'+
                '<option value="random"'+(wiz.qualifierAssignment==='random'?' selected':'')+'>Náhodný žreb + manuálna úprava</option>'+
                '<option value="ordered"'+(wiz.qualifierAssignment==='ordered'?' selected':'')+'>Podľa výsledku kvalifikácie</option>'+
                '<option value="manual"'+(wiz.qualifierAssignment==='manual'?' selected':'')+'>Manuálne</option>'+
              '</select><div class="hint">Kvalifikantov pred finále uvidíš v samostatnom zozname a pri žrebe/manuálnom režime ich potvrdíš.</div></div>'+
          '</div>';
        groupSection.parentNode.insertBefore(wrap,groupSection);
      }
      var note=Array.prototype.slice.call(panel.querySelectorAll('.note-box')).find(function(el){
        return el.textContent.indexOf('Skupinová fáza:')>=0;
      });
      if(note)note.innerHTML='<b>Kvalifikácia:</b> '+rrGroupMatchCount(wizardQualificationPlayers().length,wiz.groups)+' zápasov spolu vo všetkých skupinách.';
      var groupsInput=document.getElementById('wGroups');
      if(groupsInput){
        var hint=groupsInput.parentElement.querySelector('.hint');
        if(hint)hint.textContent='≈ '+Math.ceil(wizardQualificationPlayers().length/Math.max(1,Number(wiz.groups)||1))+' hráčov na skupinu';
      }
      refreshGroupNote();
    }

    if(wiz.step===1){
      var seedControl=panel.querySelector('.seed-control');
      if(seedControl)seedControl.remove();
      var items=panel.querySelectorAll('#seedPlayerList .pl-item');
      items.forEach(function(item,index){
        var label=item.querySelector('.pl-seed');
        if(!label)return;
        if(index<wiz.directCount){
          label.textContent='Finále #'+(index+1);
          label.classList.remove('unseeded');
        }else{
          label.textContent='Kvalifikácia';
          label.classList.add('unseeded');
        }
      });
      var bracket=panel.querySelector('.player-bracket');
      if(bracket){
        bracket.innerHTML='Finále '+wizardFinalCount()+' · pavúk '+wizardFinalBracketSize()+' · <button class="clear-all" onclick="clearPlayers()">vymazať všetkých</button>';
      }
    }

    if(wiz.step===3){
      var box=panel.querySelector('.sumbox');
      if(box&&!box.querySelector('[data-multi-stage-summary]')){
        var seedRow=Array.prototype.slice.call(box.querySelectorAll('.sumrow')).find(function(row){
          var k=row.querySelector('.k');return k&&k.textContent.trim()==='Seedovanie';
        });
        if(seedRow){
          seedRow.querySelector('.k').textContent='Priamo do finále';
          seedRow.querySelector('.v').textContent=wiz.directCount+' hráčov';
        }
        var advRow=Array.prototype.slice.call(box.querySelectorAll('.sumrow')).find(function(row){
          var k=row.querySelector('.k');return k&&k.textContent.trim()==='Postup do KO';
        });
        if(advRow){
          advRow.querySelector('.k').textContent='Kvalifikanti';
          advRow.querySelector('.v').textContent=wizardQualifierCount()+' hráčov';
        }
        var matchesRow=Array.prototype.slice.call(box.querySelectorAll('.sumrow')).find(function(row){
          var k=row.querySelector('.k');return k&&k.textContent.trim()==='Zápasy skupinovej fázy';
        });
        if(matchesRow){
          matchesRow.querySelector('.k').textContent='Zápasy kvalifikácie';
          matchesRow.querySelector('.v').textContent=rrGroupMatchCount(wizardQualificationPlayers().length,wiz.groups);
        }
        box.insertAdjacentHTML('beforeend',
          '<div class="sumrow" data-multi-stage-summary><span class="k">Viacfázový turnaj</span><span class="v">Kvalifikácia → '+finalTypeLabel({format:wiz.format})+'</span></div>'+
          '<div class="sumrow" data-multi-stage-summary><span class="k">Finálová fáza</span><span class="v">'+wizardFinalCount()+' hráčov · pavúk '+wizardFinalBracketSize()+'</span></div>'+
          '<div class="sumrow" data-multi-stage-summary><span class="k">Priradenie kvalifikantov</span><span class="v">'+assignmentLabel(wiz.qualifierAssignment)+'</span></div>'
        );
      }
    }
  }

  var originalRenderWiz=renderWiz;
  renderWiz=function(){
    if(wizardMulti()){
      wiz.directCount=clampDirect(wiz.directCount,(wiz.players||[]).length);
      wiz.seedCount=wiz.directCount;
    }
    originalRenderWiz();
    var panel=document.getElementById('wizPanel');
    if(!panel||!comboFormat(wiz.format)||wiz.formatLocked)return;
    if(wiz.step===2){
      var section=Array.prototype.slice.call(panel.querySelectorAll('.fmt-section')).find(function(el){
        return el.textContent.trim()==='Nastavenie skupín';
      });
      if(section&&!document.getElementById('multiStageToggle')){
        var toggle=document.createElement('div');
        toggle.id='multiStageToggle';
        toggle.innerHTML=
          '<div class="fmt-section">Viacfázový turnaj</div>'+
          '<div class="field"><label>Samostatná kvalifikácia + finálový turnaj</label>'+
          '<button type="button" class="presence-toggle '+(wiz.multiStage?'is-present':'')+'" role="switch" aria-checked="'+(wiz.multiStage?'true':'false')+'" onclick="setMultiStageEnabled('+(!wiz.multiStage)+')">'+
          '<span class="presence-switch" aria-hidden="true"></span><span class="presence-label">'+(wiz.multiStage?'Áno':'Nie')+'</span></button>'+
          '<div class="hint">Jeden turnaj, jedno ID. Vybraní hráči môžu byť priamo nasadení do finále, ostatní hrajú kvalifikáciu.</div></div>';
        section.parentNode.insertBefore(toggle,section);
      }
    }
    renderMultiStageWizardDecorations();
  };

  var originalRefreshGroupNote=refreshGroupNote;
  refreshGroupNote=function(){
    if(!wizardMulti())return originalRefreshGroupNote();
    var el=document.getElementById('groupNote');if(!el)return;
    var qPlayers=wizardQualificationPlayers().length;
    var qualifiers=wizardQualifierCount();
    var direct=clampDirect(wiz.directCount);
    var finalCount=direct+qualifiers;
    var koType=finalTypeLabel({format:wiz.format});
    var cap=wiz.format==='rr_dko'&&finalCount>TM.MAX_DKO_PLAYERS?'<br><b>Limit:</b> Double KO podporuje najviac '+TM.MAX_DKO_PLAYERS+' hráčov.':'';
    el.innerHTML='Kvalifikácia: <b>'+qPlayers+'</b> hráčov · postupuje <b>'+qualifiers+'</b>. Priamo vo finále: <b>'+direct+'</b>. Finálová fáza: <b>'+finalCount+'</b> hráčov → '+koType+' pavúk <b>'+TM.nextPow2(Math.max(2,finalCount))+'</b>.'+cap;
  };

  var originalRenderPreview=renderPreview;
  renderPreview=function(){
    originalRenderPreview();
    if(!wizardMulti())return;
    var el=document.getElementById('genPreview');if(!el)return;
    el.innerHTML='<div class="note-box"><b>Viacfázový turnaj:</b> '+wizardQualificationPlayers().length+' hráčov odohrá kvalifikáciu v '+wiz.groups+' skupinách. Postúpi '+wizardQualifierCount()+' kvalifikantov. K nim sa pridá '+clampDirect(wiz.directCount)+' priamo nasadených hráčov → '+finalTypeLabel({format:wiz.format})+' pavúk '+wizardFinalBracketSize()+'.<br><b>Priradenie kvalifikantov:</b> '+assignmentLabel(wiz.qualifierAssignment)+'.</div>';
  };

  var originalBuildComboGroupState=buildComboGroupState;
  buildComboGroupState=function(t,membershipRows){
    if(!tournamentMulti(t))return originalBuildComboGroupState(t,membershipRows);
    var players=qualificationPlayersFor(t);
    var G=Math.max(1,Number(t&&t.groups)||2);
    var groups=Array.from({length:G},function(_,gi){return {name:String.fromCharCode(65+gi),players:[],matches:[]};});
    var byId=new Map(players.map(function(p,i){return [p.id,Object.assign({},p,{seed:p.seed||i+1})];}));
    var assigned=new Set();
    if(Array.isArray(membershipRows)&&membershipRows.length){
      membershipRows.slice().sort(function(a,b){return Number(a.group_index)-Number(b.group_index);}).forEach(function(row){
        var gi=Number(row.group_index)-1,p=byId.get(row.player_id);
        if(gi>=0&&gi<groups.length&&p&&!assigned.has(p.id)){groups[gi].players.push(p);assigned.add(p.id);}
      });
    }
    players.forEach(function(p,i){
      if(assigned.has(p.id))return;
      var player=Object.assign({},p,{seed:p.seed||i+1});
      var gi=i%G;
      groups[gi].players.push(player);
      assigned.add(player.id);
    });
    groups.forEach(function(g){
      g.players.sort(function(a,b){return Number(a.seed||9999)-Number(b.seed||9999);});
      var rounds=TM.roundRobin(g.players);
      rounds.forEach(function(round,ri){round.forEach(function(game){
        g.matches.push({key:null,number:null,round:ri+1,p1:game[0],p2:game[1],s1:null,s2:null,winner:null});
      });});
    });
    return {groups:groups,advance:t&&t.advance};
  };

  function qualifierState(t,crossSeeded){
    var cfg=tournamentMultiConfig(t)||{};
    var mode=['ordered','random','manual'].indexOf(cfg.qualifier_assignment)>=0?cfg.qualifier_assignment:'random';
    var rows=Array.isArray(crossSeeded)?crossSeeded:[];
    var map=new Map(rows.map(function(row){return [playerKey(row.player),row];}));
    var available=rows.map(function(row){return playerKey(row.player);});
    var stored=Array.isArray(cfg.qualifier_order)?cfg.qualifier_order.map(String):[];
    var valid=stored.length===available.length&&stored.every(function(k){return map.has(k);})&&new Set(stored).size===stored.length;
    var order;
    if(mode==='ordered'){
      order=available;
    }else if(valid){
      order=stored;
    }else if(mode==='random'){
      var nonce=Number(cfg.qualifier_draw_nonce)||0;
      order=available.slice().sort(function(a,b){
        return comboDrawHash(String(t.id||'')+'|multi-stage|'+nonce+'|'+a)-comboDrawHash(String(t.id||'')+'|multi-stage|'+nonce+'|'+b);
      });
    }else{
      order=available;
    }
    if(Array.isArray(t.multiStageQualifierOrder)&&t.multiStageQualifierOrder.length===available.length){
      var local=t.multiStageQualifierOrder.map(String);
      if(local.every(function(k){return map.has(k);})&&new Set(local).size===local.length)order=local;
    }
    t.multiStageQualifierOrder=order.slice();
    t.multiStageQualifierOrderConfirmed=mode==='ordered'||cfg.qualifier_order_confirmed===true;
    return {
      mode:mode,
      order:order,
      rows:order.map(function(k){return map.get(k);}).filter(Boolean),
      confirmed:t.multiStageQualifierOrderConfirmed
    };
  }

  var originalMaybeGenerateComboPhase=maybeGenerateComboPhase;
  maybeGenerateComboPhase=function(t){
    if(!tournamentMulti(t))return originalMaybeGenerateComboPhase(t);
    if(!comboAllGroupsDone(t))return false;
    var standings=comboStandings(t);
    var crossSeeded=comboCrossSeed(standings,t.grp.groups.length,t.grp.advance,t.id||'');
    var state=qualifierState(t,crossSeeded);
    if(!state.confirmed)return false;
    if(!t.phase2){
      var finals=directPlayersFor(t).concat(state.rows.map(function(row){return row.player;}));
      if(t.format==='rr_sko'){
        t.phase2={kind:'standard-sko',qualifierCount:state.rows.length,directCount:directCountFor(t),bracket:TM.buildSKO(finals)};
      }else{
        var shortened=t.config&&t.config.dko_shortened_sko===true||(t.config&&t.config.dko_shortened_sko==null&&[4,8,16,32,64].indexOf(Number(t.config.dko_cutover_size))>=0);
        var cutover=shortened?([4,8,16,32,64].indexOf(Number(t.config.dko_cutover_size))>=0?Number(t.config.dko_cutover_size):8):2;
        t.phase2={kind:'standard-dko',qualifierCount:state.rows.length,directCount:directCountFor(t),dko:TM.buildDKO(finals,1,String(t.id||'')+':phase2',finals.length,cutover)};
      }
    }
    if(t.phase2.kind==='standard-sko')TM.recomputeSKO(t.phase2.bracket);
    else if(t.phase2.kind==='standard-dko')TM.recomputeDKO(t.phase2.dko);
    normalizeTournamentMatchIdentity(t);
    return true;
  };

  var originalComboQualifierPayload=comboQualifierPayload;
  comboQualifierPayload=function(t){
    if(!tournamentMulti(t))return originalComboQualifierPayload(t);
    var standings=comboStandings(t);
    var crossSeeded=comboCrossSeed(standings,t.grp.groups.length,t.grp.advance,t.id||'');
    var state=qualifierState(t,crossSeeded);
    if(!state.confirmed)return [];
    var direct=directCountFor(t);
    return state.rows.map(function(row,index){
      var originalIndex=crossSeeded.findIndex(function(x){return playerKey(x.player)===playerKey(row.player);});
      return {
        tournament_player_id:row.player.id,
        source_group:row.groupIndex+1,
        source_position:row.rank,
        qualification_position:index+1,
        seed:index+1,
        metadata:{
          seed_band:comboSeedBandName(row.rank),
          seeding_policy:'multi_stage_v1',
          qualification_rank:originalIndex+1,
          final_seed:direct+index+1,
          assignment_mode:state.mode
        }
      };
    });
  };

  var originalSyncComboPhaseTransition=syncComboPhaseTransition;
  syncComboPhaseTransition=async function(t){
    if(tournamentMulti(t)&&comboAllGroupsDone(t)){
      var standings=comboStandings(t);
      var crossSeeded=comboCrossSeed(standings,t.grp.groups.length,t.grp.advance,t.id||'');
      var state=qualifierState(t,crossSeeded);
      if(!state.confirmed)return null;
    }
    return originalSyncComboPhaseTransition(t);
  };

  async function saveQualifierConfig(t,confirmed){
    if(!t||!currentSession||isPublicReadOnly)return false;
    var current=t.config&&typeof t.config==='object'?t.config:{};
    var old=tournamentMultiConfig(t)||{};
    var multi=Object.assign({},old,{
      enabled:true,
      direct_count:directCountFor(t),
      qualifier_assignment:old.qualifier_assignment||'random',
      qualifier_order:(t.multiStageQualifierOrder||[]).slice(),
      qualifier_order_confirmed:!!confirmed
    });
    var next=Object.assign({},current,{multi_stage:multi});
    var result=await cspAuth.client.from('tournaments').update({config:next}).eq('id',t.id).eq('owner_id',currentSession.user.id);
    if(result.error)throw result.error;
    t.config=next;
    t.multiStageQualifierOrderConfirmed=!!confirmed;
    return true;
  }

  function rerenderMultiStageArea(){
    var area=document.getElementById('matchArea');
    if(area)area.innerHTML=renderMatchArea(curT);
    updateMatchViewControls();
  }

  window.moveMultiStageQualifier=async function(index,delta){
    if(!curT||!tournamentMulti(curT)||curT.phase2)return;
    var standings=comboStandings(curT);
    var cross=comboCrossSeed(standings,curT.grp.groups.length,curT.grp.advance,curT.id||'');
    var state=qualifierState(curT,cross);
    var target=index+delta;
    if(target<0||target>=state.order.length)return;
    var next=state.order.slice(),tmp=next[index];next[index]=next[target];next[target]=tmp;
    curT.multiStageQualifierOrder=next;
    curT.multiStageQualifierOrderConfirmed=false;
    try{await saveQualifierConfig(curT,false);}catch(err){console.error('[turnament] save qualifier order:',err);}
    rerenderMultiStageArea();
  };

  var qualifierDragIndex=null;
  window.multiStageQualifierDragStart=function(event,index){
    qualifierDragIndex=index;
    event.dataTransfer.effectAllowed='move';
    event.dataTransfer.setData('text/plain',String(index));
    event.currentTarget.classList.add('dragging');
  };
  window.multiStageQualifierDragOver=function(event){
    event.preventDefault();
    event.dataTransfer.dropEffect='move';
    event.currentTarget.classList.add('drag-over');
  };
  window.multiStageQualifierDragLeave=function(event){event.currentTarget.classList.remove('drag-over');};
  window.multiStageQualifierDragEnd=function(event){
    qualifierDragIndex=null;
    event.currentTarget.classList.remove('dragging');
    document.querySelectorAll('.multi-stage-qualifier.drag-over').forEach(function(el){el.classList.remove('drag-over');});
  };
  window.multiStageQualifierDrop=async function(event,targetIndex){
    event.preventDefault();
    var source=qualifierDragIndex;
    if(source==null)source=Number(event.dataTransfer.getData('text/plain'));
    qualifierDragIndex=null;
    if(!Number.isInteger(source)||source===targetIndex)return rerenderMultiStageArea();
    var standings=comboStandings(curT);
    var cross=comboCrossSeed(standings,curT.grp.groups.length,curT.grp.advance,curT.id||'');
    var state=qualifierState(curT,cross);
    var next=state.order.slice();
    var moved=next.splice(source,1)[0];
    next.splice(targetIndex,0,moved);
    curT.multiStageQualifierOrder=next;
    curT.multiStageQualifierOrderConfirmed=false;
    try{await saveQualifierConfig(curT,false);}catch(err){console.error('[turnament] save qualifier order:',err);}
    rerenderMultiStageArea();
  };

  window.confirmMultiStageQualifiers=async function(){
    if(!curT||!tournamentMulti(curT)||!comboAllGroupsDone(curT))return;
    pendingTournamentWrite=true;
    try{
      var standings=comboStandings(curT);
      var cross=comboCrossSeed(standings,curT.grp.groups.length,curT.grp.advance,curT.id||'');
      var state=qualifierState(curT,cross);
      if(!state.order.length)throw new Error('Chýbajú kvalifikanti.');
      await saveQualifierConfig(curT,true);
      maybeGenerateComboPhase(curT);
      await syncComboPhaseTransition(curT);
      await persistT();
      comboPhaseView='final';
      matchViewMode='bracket';
      rerenderMultiStageArea();
      toast('Kvalifikácia uzavretá — finálový pavúk je pripravený ✓');
    }catch(err){
      console.error('[turnament] confirm multi-stage qualifiers:',err);
      toast('Finálový pavúk sa nepodarilo vytvoriť: '+cspErrorMessage(err),true);
    }finally{
      pendingTournamentWrite=false;
    }
  };

  function qualifierPanel(t){
    if(!tournamentMulti(t))return '';
    var direct=directPlayersFor(t);
    var directHtml='<div class="note-box" style="margin-bottom:16px"><b>PRIAMO VO FINÁLE · '+direct.length+'</b>';
    if(direct.length){
      directHtml+='<div style="margin-top:8px;display:grid;gap:6px">'+direct.map(function(p,i){
        return '<div class="pl-item" style="padding:9px 12px"><span class="pl-seed">Seed '+(i+1)+'</span><span class="pl-name">'+esc(p.name)+'</span></div>';
      }).join('')+'</div>';
    }else directHtml+='<div class="hint" style="margin-top:6px">Bez priamo nasadených hráčov.</div>';
    directHtml+='</div>';
    if(!comboAllGroupsDone(t))return directHtml;

    var standings=comboStandings(t);
    var cross=comboCrossSeed(standings,t.grp.groups.length,t.grp.advance,t.id||'');
    var state=qualifierState(t,cross);
    var directCount=directCountFor(t);
    var editable=!isPublicReadOnly&&!t.phase2&&state.mode!=='ordered'&&!state.confirmed;
    var rows=state.rows.map(function(row,index){
      var attrs=editable?' draggable="true" ondragstart="multiStageQualifierDragStart(event,'+index+')" ondragover="multiStageQualifierDragOver(event)" ondragleave="multiStageQualifierDragLeave(event)" ondrop="multiStageQualifierDrop(event,'+index+')" ondragend="multiStageQualifierDragEnd(event)"':'';
      var buttons=editable?'<span class="pl-move"><button type="button" onclick="moveMultiStageQualifier('+index+',-1)" title="Vyššie">▲</button><button type="button" onclick="moveMultiStageQualifier('+index+',1)" title="Nižšie">▼</button></span>':'';
      return '<div class="pl-item multi-stage-qualifier"'+attrs+' style="padding:9px 12px">'+
        (editable?'<span class="pl-drag">☰</span>':'')+
        '<span class="pl-seed">Finále #'+(directCount+index+1)+'</span>'+
        '<span class="pl-name">'+esc(row.player.name)+' <span class="muted" style="font-size:.74rem">· '+esc(qualificationSourceLabel(row))+'</span></span>'+
        buttons+'</div>';
    }).join('');

    var action='';
    if(!isPublicReadOnly&&!t.phase2&&state.mode!=='ordered'&&!state.confirmed){
      action='<div style="display:flex;justify-content:flex-end;margin-top:12px"><button class="btn btn-green" onclick="confirmMultiStageQualifiers()">✓ Potvrdiť nasadenie do finále</button></div>';
    }
    var status=t.phase2?'<div class="hint" style="margin-top:8px">✓ Nasadenie potvrdené a finálová fáza vytvorená.</div>':
      (state.mode==='ordered'?'<div class="hint" style="margin-top:8px">Poradie sa vytvorí automaticky podľa výsledku kvalifikácie.</div>':'<div class="hint" style="margin-top:8px">Poradie môžeš pred potvrdením upraviť potiahnutím alebo šípkami.</div>');
    return directHtml+
      '<div class="note-box" style="margin-bottom:16px"><b>POSTUPUJÚ DO FINÁLOVEJ FÁZY · '+state.rows.length+' KVALIFIKANTOV</b>'+
      '<div class="hint" style="margin:5px 0 10px">Priradenie: '+esc(assignmentLabel(state.mode))+' · finálový '+finalTypeLabel(t)+' pavúk '+TM.nextPow2(Math.max(2,direct.length+state.rows.length))+'</div>'+
      '<div style="display:grid;gap:6px">'+rows+'</div>'+status+action+'</div>';
  }

  var originalRenderComboGroupList=renderComboGroupList;
  renderComboGroupList=function(t){
    if(!tournamentMulti(t))return originalRenderComboGroupList(t);
    var html=originalRenderComboGroupList(t);
    var firstClose=html.indexOf('</div>');
    if(firstClose>=0){
      var intro='<div class="note-box" style="margin-bottom:16px"><b>Kvalifikácia</b> · '+qualificationPlayersFor(t).length+' hráčov · '+t.grp.groups.length+' skupín · postupuje '+comboStandings(t).length+' z plánovaných '+comboQualifierCount(qualificationPlayersFor(t).length,t.grp.groups.length,t.grp.advance)+'. Kvalifikanti sa spoja s '+directCountFor(t)+' priamo nasadenými hráčmi vo finálovom '+finalTypeLabel(t)+' pavúku.</div>';
      html=intro+html.slice(firstClose+6);
    }
    html=html.replace(/Skupinová fáza/g,'Kvalifikácia');
    if(comboAllGroupsDone(t)&&!t.phase2){
      html=html.replace('✓ Skupiny dohrané — generujem Finálovú fázu…','✓ Kvalifikácia dohraná — skontroluj a potvrď nasadenie kvalifikantov do finále.');
    }
    return qualifierPanel(t)+html;
  };

  var originalRenderComboPhaseNav=renderComboPhaseNav;
  renderComboPhaseNav=function(t){
    var html=originalRenderComboPhaseNav(t);
    if(!tournamentMulti(t))return html;
    return html.replace('Skupinová fáza','Kvalifikácia').replace('Finálová fáza','Finálový turnaj');
  };

  var originalUpdateMatchViewControls=updateMatchViewControls;
  updateMatchViewControls=function(){
    originalUpdateMatchViewControls();
    if(!tournamentMulti(curT))return;
    var title=document.getElementById('matchViewTitle');
    if(title)title.textContent=comboPhaseView==='final'?'Finálový turnaj':'Kvalifikácia';
  };

  var originalRenderComboPhase2=renderComboPhase2;
  renderComboPhase2=function(phase){
    var html=originalRenderComboPhase2(phase);
    if(tournamentMulti(curT))html=html.replace(/Phase 2/g,'Finálový turnaj');
    return html;
  };

  var originalViewDetail=viewDetail;
  viewDetail=async function(id){
    var html=await originalViewDetail(id);
    if(tournamentMulti(curT)){
      html=html.replace('>Skupiny → Single KO<','>Viacfázový · Kvalifikácia → Single KO<');
      html=html.replace('>Skupiny → Double KO<','>Viacfázový · Kvalifikácia → Double KO<');
    }
    return html;
  };

  var originalCreateTournament=createTournament;
  createTournament=async function(){
    var activeMulti=wizardMulti();
    var tournamentId=wiz&&wiz.editId?wiz.editId:null;
    if(activeMulti){
      captureWizardInputs();
      var qPlayers=wizardQualificationPlayers();
      if(qPlayers.length<2){toast('Kvalifikácia potrebuje aspoň 2 hráčov.',true);return;}
      var finalCount=wizardFinalCount();
      if(wiz.format==='rr_dko'&&finalCount>TM.MAX_DKO_PLAYERS){
        toast('Finálový Double KO podporuje najviac '+TM.MAX_DKO_PLAYERS+' hráčov.',true);return;
      }
      wiz.directCount=clampDirect(wiz.directCount,(wiz.players||[]).length);
      wiz.seedCount=wiz.directCount;
      var existing=wiz.config&&typeof wiz.config==='object'?wiz.config:{};
      wiz.config=Object.assign({},existing,{
        multi_stage:{
          enabled:true,
          direct_count:wiz.directCount,
          qualifier_assignment:['ordered','random','manual'].indexOf(wiz.qualifierAssignment)>=0?wiz.qualifierAssignment:'random',
          qualifier_order:[],
          qualifier_order_confirmed:false,
          version:1
        }
      });
    }else if(comboFormat(wiz&&wiz.format)&&wiz&&wiz.config&&wiz.config.multi_stage){
      wiz.config=Object.assign({},wiz.config,{multi_stage:null});
    }

    await originalCreateTournament();

    if(activeMulti&&tournamentId){
      try{
        var res=await cspAuth.client.from('tournament_players').select('id,seed').eq('tournament_id',tournamentId).order('seed',{ascending:true});
        if(res.error)throw res.error;
        var directIds=(res.data||[]).slice(0,wiz.directCount).map(function(p){return p.id;});
        if(directIds.length){
          var del=await cspAuth.client.from('tournament_groups').delete().eq('tournament_id',tournamentId).in('player_id',directIds);
          if(del.error)throw del.error;
        }
      }catch(err){
        console.error('[turnament] multi-stage group cleanup:',err);
      }
    }
  };

  var style=document.createElement('style');
  style.textContent='.multi-stage-qualifier.drag-over{outline:1px solid var(--gold);background:var(--gold-dim)} .multi-stage-qualifier.dragging{opacity:.55}';
  document.head.appendChild(style);
})();