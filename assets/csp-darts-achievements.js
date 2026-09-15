(function(global){
  'use strict';

  if(!/^\/scoreboard\/?$/.test(global.location.pathname))return;

  function install(){
    if(typeof global.submitRunDarts!=='function')return false;
    if(global.submitRunDarts.__cspDartsAchievementsWrapped)return true;

    var original=global.submitRunDarts;

    function record(snapshot){
      setTimeout(async function(){
        try{
          if(!snapshot||!global.cspAuth||!global.cspAuth.client)return;
          if(typeof ensureTrainingEventSession!=='function')return;
          var sessionId=await ensureTrainingEventSession();
          if(!sessionId)return;
          var r=await global.cspAuth.client.rpc('record_darts_visit',{
            p_training_session_id:sessionId,
            p_discipline:snapshot.discipline,
            p_score:snapshot.score,
            p_remaining_before:snapshot.before,
            p_remaining_after:snapshot.after,
            p_is_bust:snapshot.bust
          });
          if(r.error)console.warn('[csp-darts-achievements] record failed',r.error);
        }catch(err){
          console.warn('[csp-darts-achievements] record failed',err);
        }
      },0);
    }

    var wrapped=function(){
      var snapshot=null;
      try{
        var tournamentActive=(typeof MATCH_ID!=='undefined'&&MATCH_ID)||(typeof MATCH_TOKEN!=='undefined'&&MATCH_TOKEN);
        if(typeof mode==='function'&&mode()==='darts'&&!tournamentActive&&typeof state!=='undefined'&&state.currentIndex===0){
          var players=typeof activePlayers==='function'?activePlayers():[];
          var p=players[state.currentIndex];
          var score=Number(state.runInput||0);
          if(p&&Number.isFinite(score)&&score>=0&&score<=180){
            var before=Number(p.remaining||0);
            var left=before-score;
            var bust=left<0||Boolean(state.doubleOut&&left===1);
            snapshot={
              score:score,
              before:before,
              after:bust?before:left,
              bust:bust,
              discipline:typeof currentDisciplineLabel==='function'?currentDisciplineLabel():'501'
            };
          }
        }
      }catch(err){
        console.warn('[csp-darts-achievements] snapshot failed',err);
      }

      var result=original.apply(this,arguments);
      if(snapshot)record(snapshot);
      return result;
    };

    wrapped.__cspDartsAchievementsWrapped=true;
    global.submitRunDarts=wrapped;
    return true;
  }

  function start(){
    if(install())return;
    var attempts=0;
    var timer=setInterval(function(){
      attempts++;
      if(install()||attempts>=40)clearInterval(timer);
    },250);
  }

  if(document.readyState==='complete')start();
  else global.addEventListener('load',start,{once:true});
})(window);
