(function(global){
  'use strict';

  function winsNeeded(totalLegs){
    var total=Math.max(1,parseInt(totalLegs,10)||1);
    return Math.floor(total/2)+1;
  }

  function isDarts(){
    try{return typeof mode==='function'&&mode()==='darts'}catch(_e){return false}
  }

  function normalizeLegInput(){
    var input=document.getElementById('raceTo');
    if(!input||!isDarts())return;
    input.min='1';
    input.max='99';
    input.step='2';
    var value=Math.max(1,parseInt(input.value,10)||5);
    if(value%2===0)value+=1;
    input.value=String(value);
    try{state.raceTo=value}catch(_e){}
  }

  function syncLabels(){
    if(!isDarts())return;
    var total=Math.max(1,parseInt((document.getElementById('raceTo')||{}).value,10)||Number(state&&state.raceTo)||5);
    var needed=winsNeeded(total);
    var label=document.getElementById('raceLabel');
    if(label)label.textContent='Počet legov (Best of)';
    var pill=document.getElementById('formatPill');
    if(pill)pill.textContent='Best of '+total+' · na '+needed+' víťazné legy';
    var nextLabel=document.getElementById('nextSetRaceLabel');
    if(nextLabel)nextLabel.textContent='Počet legov (Best of) pre ďalší set';
    var nextInput=document.getElementById('nextSetRaceTo');
    if(nextInput){nextInput.min='1';nextInput.max='99';nextInput.step='2';}
  }

  function install(){
    if(typeof global.dartsWinLeg!=='function'||typeof global.render!=='function'){
      setTimeout(install,50);
      return;
    }

    var originalRender=global.render;
    global.render=function(){
      var result=originalRender.apply(this,arguments);
      syncLabels();
      return result;
    };

    if(typeof global.applySettings==='function'){
      var originalApplySettings=global.applySettings;
      global.applySettings=function(){
        var sportSelect=document.getElementById('sportSelect');
        if((sportSelect&&sportSelect.value==='darts')||isDarts())normalizeLegInput();
        var result=originalApplySettings.apply(this,arguments);
        syncLabels();
        return result;
      };
    }

    global.dartsWinLeg=function(i){
      invalidateScoreEventUndo();
      var w=activePlayers()[i];
      w.legs++;
      addLog('🎯 '+w.name+' vyhral leg '+state.period+'!');

      var totalLegs=Math.max(1,Number(state.raceTo)||1);
      if(totalLegs%2===0)totalLegs+=1;
      var targetWins=winsNeeded(totalLegs);

      if(w.legs>=targetWins){
        addLog('🏆 '+w.name+' vyhral zápas '+w.legs+':'+activePlayers().filter(function(_p,idx){return idx!==i}).map(function(p){return p.legs}).join('/')+' (Best of '+totalLegs+')');
        prepareTrainingSummary({mode:'darts',bestOf:totalLegs,players:activePlayers().map(function(p){return {name:p.name,legs:p.legs}})},w.name,elapsedSeconds());
        state.period++;
        state.starter=(state.starter+1)%state.playerCount;
        state.currentIndex=state.starter;
        state.runInput='';
        activePlayers().forEach(function(p){p.remaining=startScore()});
        render();
        showMatchWonDialog(i,'darts');
        return;
      }

      state.period++;
      state.starter=(state.starter+1)%state.playerCount;
      state.currentIndex=state.starter;
      state.runInput='';
      activePlayers().forEach(function(p){p.remaining=startScore()});
      render();
    };

    var raceInput=document.getElementById('raceTo');
    if(raceInput){
      raceInput.addEventListener('change',function(){normalizeLegInput();syncLabels()});
      raceInput.addEventListener('blur',function(){normalizeLegInput();syncLabels()});
    }
    var nextInput=document.getElementById('nextSetRaceTo');
    if(nextInput){
      nextInput.addEventListener('change',function(){
        var n=Math.max(1,parseInt(nextInput.value,10)||5);
        if(n%2===0)n+=1;
        nextInput.value=String(n);
      });
    }

    normalizeLegInput();
    syncLabels();
  }

  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install,{once:true});
  else install();
})(window);
