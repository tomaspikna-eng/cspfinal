import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";

const root=path.resolve(import.meta.dirname,"..");
const html=fs.readFileSync(path.join(root,"turnament/index.html"),"utf8");
const start=html.indexOf("const TM = {");
const end=html.indexOf("\n\nfunction dkoMatchesInNumberOrder",start);
assert.ok(start>=0&&end>start,"Tournament engine sa nepodarilo načítať.");

const context={console};
vm.runInNewContext(html.slice(start,end)+"\n;globalThis.__TM=TM;",context);
const TM=context.__TM;
const bronzeStart=html.indexOf("function loserOf(");
const bronzeEnd=html.indexOf("/* ── GROUPS",bronzeStart);
assert.ok(bronzeStart>=0&&bronzeEnd>bronzeStart,"Logiku zápasu o tretie miesto sa nepodarilo načítať.");
vm.runInNewContext(
  html.slice(bronzeStart,bronzeEnd)+"\n;globalThis.__syncThirdPlaceMatch=syncThirdPlaceMatch;globalThis.__thirdPlaceRequired=thirdPlaceRequired;",
  context
);

function matches(dko){
  return [
    ...(dko.W||[]).flat(),
    ...(dko.L||[]).flat(),
    ...(dko.QF||[]),
    ...(dko.SF||[]),
    ...(dko.F?[dko.F]:[])
  ];
}

function finish(dko){
  for(let pass=0;pass<1000&&!dko.F.winner;pass++){
    TM.recomputeDKO(dko);
    let changed=false;
    for(const match of matches(dko)){
      if(match.winner||!match.p1||!match.p2||match.p1.bye||match.p2.bye)continue;
      match.s1=5;
      match.s2=3;
      match.winner=1;
      match.resultSig=TM.matchSig(match);
      changed=true;
    }
    if(!changed)TM.recomputeDKO(dko);
  }
  TM.recomputeDKO(dko);
}

for(const count of [16,32,64,128,256]){
  const players=Array.from({length:count},function(_,index){
    return {id:"p"+(index+1),name:"Hráč "+(index+1)};
  });
  const dko=TM.buildDKO(players,1,"test-"+count);
  assert.equal(dko.N,count,count+" hráčov musí mať pavúk rovnakej veľkosti.");
  assert.equal(dko.W[0].filter(function(match){return match.p1?.bye||match.p2?.bye}).length,0,count+" hráčov nesmie dostať W.O.");
  finish(dko);
  assert.ok(dko.F.winner,count+"-hráčsky DKO sa nedokončil.");
  const ranking=TM.dkoRanking(dko);
  assert.equal(ranking.length,count,count+"-hráčsky rebríček nemá všetkých hráčov.");
  assert.equal(new Set(ranking.map(function(row){return row.name})).size,count,count+"-hráčsky rebríček obsahuje duplicitu.");
  assert.equal(ranking[0].place,1,"Víťaz nemá prvé miesto.");
  assert.equal(ranking[1].place,2,"Finalista nemá druhé miesto.");
}

const skoPlayers=Array.from({length:16},function(_,index){
  return {id:"s"+(index+1),name:"SKO hráč "+(index+1)};
});
const sko=TM.buildSKO(skoPlayers);
for(let pass=0;pass<100&&!sko.rounds.at(-1)[0].winner;pass++){
  TM.recomputeSKO(sko);
  for(const round of sko.rounds){
    for(const match of round){
      if(match.winner||!match.p1||!match.p2||match.p1.bye||match.p2.bye)continue;
      match.s1=5;
      match.s2=3;
      match.winner=1;
      match.resultSig=TM.matchSig(match);
    }
  }
}
TM.recomputeSKO(sko);
const tournament={format:"sko",config:{third_place_playoff:true},bracket:sko,players:skoPlayers};
assert.equal(context.__thirdPlaceRequired(tournament),true,"Bronzový zápas sa nevyžaduje.");
const bronze=context.__syncThirdPlaceMatch(tournament);
assert.ok(bronze?.p1&&bronze?.p2,"Bronzový zápas nemá oboch porazených semifinalistov.");
assert.notEqual(bronze.p1.name,bronze.p2.name,"Bronzový zápas obsahuje toho istého hráča dvakrát.");

console.log("OK: DKO engine pre 16, 32, 64, 128 a 256 hráčov.");
console.log("OK: prepínač vytvorí zápas porazených semifinalistov o tretie miesto.");
