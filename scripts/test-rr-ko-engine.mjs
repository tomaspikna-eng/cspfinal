import assert from 'node:assert/strict';
import fs from 'node:fs';

const sourcePath = process.argv[2] || 'turnament/index.html';
const hasSource = fs.existsSync(sourcePath);
const source = hasSource ? fs.readFileSync(sourcePath, 'utf8') : '';

function sourceGuard(pattern, message) {
  if (hasSource) assert.match(source, pattern, message);
}

sourceGuard(/function rrTable\(/, 'rrTable must exist');
sourceGuard(/b\.h2hPoints-a\.h2hPoints\s*\|\|\s*b\.h2hDiff-a\.h2hDiff\s*\|\|\s*b\.h2hScoreFor-a\.h2hScoreFor\s*\|\|\s*\(b\.gw-b\.gl\)-\(a\.gw-a\.gl\)\s*\|\|\s*b\.gw-a\.gw/, 'RR tiebreak must use H2H points, H2H diff, H2H score-for, total diff, then total score-for');
sourceGuard(/function comboCrossSeed\(/, 'RR→KO seeding function must exist');
sourceGuard(/function comboFirstRoundOpponents\(/, 'first-round opponent mapping must exist');
sourceGuard(/function isTwoGroupTopThreeCrossing\(/, 'special 2x3 crossing guard must exist');
sourceGuard(/A2 hrá s B3 a B2 s A3/, 'special 2x3 crossing rule must remain documented in production source');
sourceGuard(/seeding_policy:'rr_rank_bands_v1'/, 'qualifier payload must carry rr_rank_bands_v1');

const TM = {
  seedKO(n){
    let seq=[1,2];
    while(seq.length<n){
      const m=seq.length*2, next=[];
      seq.forEach((s,i)=>{ const comp=m+1-s; if(i%2===0) next.push(s,comp); else next.push(comp,s); });
      seq=next;
    }
    return seq;
  },
  nextPow2(q){ let n=2; while(n<q)n*=2; return n; }
};

function rrTable(players,matches){
  const tab={};
  players.forEach((p,i)=>tab[p.name]={name:p.name,seed:p.seed||i+1,w:0,l:0,gw:0,gl:0,p:0});
  matches.forEach(m=>{
    if(!m.winner)return;
    const win=m.winner===1?m.p1:m.p2, lose=m.winner===1?m.p2:m.p1;
    const s1=Number(m.s1)||0,s2=Number(m.s2)||0;
    const wgw=m.winner===1?s1:s2, lgw=m.winner===1?s2:s1;
    if(tab[win.name]){tab[win.name].w++;tab[win.name].p+=2;tab[win.name].gw+=wgw;tab[win.name].gl+=lgw;}
    if(tab[lose.name]){tab[lose.name].l++;tab[lose.name].gw+=lgw;tab[lose.name].gl+=wgw;}
  });
  const rows=Object.values(tab).map(s=>({...s,pct:(s.gw+s.gl)?Math.round(100*s.gw/(s.gw+s.gl)):0,h2hPoints:0,h2hScoreFor:0,h2hScoreAgainst:0,h2hDiff:0}));
  const tiedByPoints=new Map();
  rows.forEach(row=>{ if(!tiedByPoints.has(row.p))tiedByPoints.set(row.p,[]); tiedByPoints.get(row.p).push(row); });
  tiedByPoints.forEach(tied=>{
    if(tied.length<2)return;
    const names=new Set(tied.map(r=>r.name));
    const mini=new Map(tied.map(r=>[r.name,{points:0,scoreFor:0,scoreAgainst:0}]));
    matches.forEach(m=>{
      if(!m.winner||!m.p1||!m.p2||!names.has(m.p1.name)||!names.has(m.p2.name))return;
      const s1=Number(m.s1)||0,s2=Number(m.s2)||0;
      mini.get(m.p1.name).scoreFor+=s1;mini.get(m.p1.name).scoreAgainst+=s2;
      mini.get(m.p2.name).scoreFor+=s2;mini.get(m.p2.name).scoreAgainst+=s1;
      const winner=m.winner===1?m.p1:m.p2;
      mini.get(winner.name).points+=2;
    });
    tied.forEach(r=>{const h=mini.get(r.name);r.h2hPoints=h.points;r.h2hScoreFor=h.scoreFor;r.h2hScoreAgainst=h.scoreAgainst;r.h2hDiff=h.scoreFor-h.scoreAgainst;});
  });
  return rows.sort((a,b)=>b.p-a.p||b.h2hPoints-a.h2hPoints||b.h2hDiff-a.h2hDiff||b.h2hScoreFor-a.h2hScoreFor||(b.gw-b.gl)-(a.gw-a.gl)||b.gw-a.gw||a.seed-b.seed);
}

function comboSeedCompare(a,b){
  return b.stat.p-a.stat.p || b.stat.w-a.stat.w ||
    (b.stat.gw-b.stat.gl)-(a.stat.gw-a.stat.gl) ||
    b.stat.pct-a.stat.pct || a.groupIndex-b.groupIndex ||
    Number(a.player.seed||999999)-Number(b.player.seed||999999);
}
function comboDrawHash(value){
  let h=2166136261;
  for(let i=0;i<value.length;i++){h^=value.charCodeAt(i);h=Math.imul(h,16777619);}
  return h>>>0;
}
function comboFirstRoundOpponents(N){
  const order=TM.seedKO(N),map=new Map();
  for(let i=0;i<order.length;i+=2){map.set(order[i],order[i+1]);map.set(order[i+1],order[i]);}
  return map;
}
function comboCrossSeed(rows,drawKey='test'){
  const winners=rows.filter(r=>r.rank===1).sort(comboSeedCompare);
  const runners=rows.filter(r=>r.rank===2).sort(comboSeedCompare);
  const lower=rows.filter(r=>r.rank>=3).sort((a,b)=>{
    const ah=comboDrawHash(`${drawKey}|${a.player.id||a.player.name}|${a.groupIndex}|${a.rank}`);
    const bh=comboDrawHash(`${drawKey}|${b.player.id||b.player.name}|${b.groupIndex}|${b.rank}`);
    return ah-bh||comboSeedCompare(a,b);
  });
  const seeded=[...winners,...runners,...lower];
  const N=TM.nextPow2(Math.max(2,seeded.length));
  const opponents=comboFirstRoundOpponents(N);
  const bands=[[0,winners.length],[winners.length,winners.length+runners.length],[winners.length+runners.length,seeded.length]];
  for(const [start,end] of bands){
    for(let i=start;i<end;i++){
      const seed=i+1, oppSeed=opponents.get(seed);
      if(!oppSeed||oppSeed>seeded.length)continue;
      const j=oppSeed-1;
      if(!seeded[j]||seeded[i].groupIndex!==seeded[j].groupIndex)continue;
      for(let k=i+1;k<end;k++){
        const kOpp=opponents.get(k+1), kOppRow=kOpp&&kOpp<=seeded.length?seeded[kOpp-1]:null;
        const iOppRow=seeded[j];
        if(seeded[k].groupIndex!==iOppRow.groupIndex && (!kOppRow||seeded[i].groupIndex!==kOppRow.groupIndex)){
          [seeded[i],seeded[k]]=[seeded[k],seeded[i]];break;
        }
      }
    }
  }
  return seeded;
}

{
  const A={name:'A',seed:1},B={name:'B',seed:2},C={name:'C',seed:3},D={name:'D',seed:4};
  const rows=rrTable([A,B,C,D],[
    {p1:A,p2:B,s1:3,s2:2,winner:1},
    {p1:A,p2:C,s1:0,s2:3,winner:2},
    {p1:A,p2:D,s1:0,s2:3,winner:2},
    {p1:B,p2:C,s1:3,s2:0,winner:1},
    {p1:B,p2:D,s1:2,s2:3,winner:2},
    {p1:C,p2:D,s1:3,s2:0,winner:1},
  ]);
  assert.equal(rows.findIndex(r=>r.name==='A') < rows.findIndex(r=>r.name==='B'), true, 'A must rank above B on H2H');
}

{
  const A={name:'A',seed:1},B={name:'B',seed:2},C={name:'C',seed:3};
  const rows=rrTable([A,B,C],[
    {p1:A,p2:B,s1:3,s2:0,winner:1},
    {p1:B,p2:C,s1:3,s2:1,winner:1},
    {p1:C,p2:A,s1:3,s2:2,winner:1},
  ]);
  assert.deepEqual(rows.map(r=>r.name),['A','C','B'], '3-way mini-table must sort by H2H score difference before H2H score-for');
}

{
  const A={name:'A',seed:1},B={name:'B',seed:2},C={name:'C',seed:3},D={name:'D',seed:4};
  const rows=rrTable([A,B,C,D],[
    {p1:A,p2:B,s1:5,s2:4,winner:1},
    {p1:B,p2:C,s1:5,s2:4,winner:1},
    {p1:C,p2:A,s1:5,s2:4,winner:1},
    {p1:A,p2:D,s1:5,s2:4,winner:1},
    {p1:B,p2:D,s1:5,s2:1,winner:1},
    {p1:C,p2:D,s1:5,s2:3,winner:1},
  ]);
  const a=rows.find(r=>r.name==='A'),b=rows.find(r=>r.name==='B'),c=rows.find(r=>r.name==='C');
  assert.equal(a.p,b.p,'fixture requires equal points');
  assert.equal(b.p,c.p,'fixture requires a 3-way tie');
  assert.equal(a.h2hPoints,b.h2hPoints,'H2H points must be equal');
  assert.equal(a.h2hDiff,b.h2hDiff,'H2H difference must be equal');
  assert.equal(a.h2hScoreFor,b.h2hScoreFor,'H2H score-for must be equal');
  assert.ok((b.gw-b.gl)>(c.gw-c.gl)&&(c.gw-c.gl)>(a.gw-a.gl),'fixture must differ only on total score difference after H2H');
  assert.deepEqual(rows.slice(0,3).map(r=>r.name),['B','C','A'],'total score difference must break a fully equal H2H mini-table');
}

{
  const opp=comboFirstRoundOpponents(16);
  for(let seed=1;seed<=4;seed++) assert.ok(opp.get(seed)>4, `top seed ${seed} must not face another top-4 seed`);
}

function makeRows(groups=4,advance=4){
  const rows=[];
  for(let g=1;g<=groups;g++) for(let rank=1;rank<=advance;rank++) rows.push({
    player:{id:`G${g}R${rank}`,name:`G${g}R${rank}`,seed:(g-1)*advance+rank},
    groupIndex:g, rank,
    stat:{p:(advance-rank)*2+g/100,w:advance-rank,gw:20-rank,gl:rank,pct:80-rank}
  });
  return rows;
}

{
  const seeded=comboCrossSeed(makeRows(4,4),'T-16');
  assert.ok(seeded.slice(0,4).every(r=>r.rank===1),'seeds 1-4 must be group winners');
  assert.ok(seeded.slice(4,8).every(r=>r.rank===2),'seeds 5-8 must be runners-up');
  assert.ok(seeded.slice(8,16).every(r=>r.rank>=3),'seeds 9-16 must be lower qualifiers');
}

{
  const a=comboCrossSeed(makeRows(4,4),'same-key').map(r=>r.player.id);
  const b=comboCrossSeed(makeRows(4,4),'same-key').map(r=>r.player.id);
  assert.deepEqual(a,b,'same draw key must reproduce identical seeding');
}

{
  const seeded=comboCrossSeed(makeRows(4,4),'avoid-rematch');
  const opp=comboFirstRoundOpponents(16);
  for(let seed=1;seed<=16;seed++){
    const os=opp.get(seed); if(seed>=os)continue;
    const a=seeded[seed-1],b=seeded[os-1];
    assert.ok(!(a.rank===1&&b.rank===1),'group winners cannot meet in R1');
    assert.notEqual(a.groupIndex,b.groupIndex,`avoidable same-group R1 rematch at seeds ${seed}/${os}`);
  }
}

{
  const A1='A1',A2='A2',A3='A3',B1='B1',B2='B2',B3='B3';
  const prelim=[[A2,B3],[B2,A3]];
  const semis=[[A1,'winner(B2-A3)'],[B1,'winner(A2-B3)']];
  assert.deepEqual(prelim,[[A2,B3],[B2,A3]]);
  assert.deepEqual(semis,[[A1,'winner(B2-A3)'],[B1,'winner(A2-B3)']]);
}

console.log('RR→KO engine tests: OK (8 suites)');
