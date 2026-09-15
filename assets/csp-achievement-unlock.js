(function(global){
  'use strict';

  var bound=false;
  var channel=null;
  var queue=[];
  var showing=false;

  var LABELS={
    first_step:'01',first_match:'▶',first_win:'V',first_tournament:'T',first_training:'TR',
    matches_10:'10',matches_25:'25',matches_50:'50',matches_100:'100',wins_5:'5V',wins_10:'10V',wins_50:'50V',wins_100:'100V',
    win_streak_3:'3×',win_streak_5:'5×',win_streak_10:'10×',group_winner:'G1',top_8:'TOP8',semifinal:'SF',finalist:'F',
    champion:'1',clean_tournament:'0L',champion_2:'2×',champion_5:'5×',tournaments_10:'10T'
  };

  function esc(v){return String(v==null?'':v).replace(/[&<>"']/g,function(c){return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]})}
  function codeFrom(n){
    try{return new URL(n.action_url||'',global.location.origin).searchParams.get('achievement')||''}catch(_){return''}
  }
  function parse(n){
    var body=String(n.body||'');
    var parts=body.split(' · ');
    var tier=(parts[0]||'Bronze').trim();
    var points=(parts[1]||'').trim();
    var description=parts.slice(2).join(' · ').trim();
    var code=codeFrom(n);
    var title=String(n.title||'Achievement odomknutý').replace(/^Achievement odomknutý:\s*/i,'');
    return {title:title,tier:tier,points:points,description:description,code:code,symbol:LABELS[code]||'CSP',url:n.action_url||'/profil/achievements/'};
  }
  function tierClass(t){
    t=String(t||'').toLowerCase();
    return ['bronze','silver','gold','platinum'].indexOf(t)>=0?t:'bronze';
  }
  function injectStyles(){
    if(document.getElementById('csp-achievement-unlock-style'))return;
    var s=document.createElement('style');
    s.id='csp-achievement-unlock-style';
    s.textContent=`
      .csp-achievement-overlay{position:fixed;inset:0;z-index:2147483000;display:grid;place-items:center;padding:18px;background:rgba(0,0,0,.72);backdrop-filter:blur(7px);animation:cspAchFade .18s ease both}
      .csp-achievement-popup{width:min(430px,100%);position:relative;overflow:hidden;border:1px solid rgba(212,168,67,.38);border-radius:20px;background:radial-gradient(circle at 50% 0,rgba(212,168,67,.13),transparent 38%),linear-gradient(160deg,#121512,#090b0a);box-shadow:0 28px 90px rgba(0,0,0,.72);padding:28px 24px 22px;text-align:center;color:#f4f4f2;animation:cspAchRise .28s cubic-bezier(.2,.8,.2,1) both}
      .csp-achievement-kicker{font:800 10px/1.2 ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:.19em;color:#22d36b;text-transform:uppercase;margin-bottom:16px}
      .csp-achievement-seal-wrap{height:166px;display:grid;place-items:center}
      .csp-achievement-seal{--m1:#c8864a;--m2:#5d3420;--m3:#e3a970;--ring:#a86c3a;width:148px;height:148px;position:relative;border-radius:50%;background:conic-gradient(from 0deg,var(--m1),var(--m2),var(--m3),var(--m2),var(--m1));clip-path:polygon(50% 0,58% 6%,68% 2%,75% 10%,85% 9%,90% 19%,98% 25%,94% 36%,100% 45%,95% 54%,98% 65%,89% 72%,86% 82%,75% 84%,68% 95%,58% 92%,50% 100%,41% 93%,31% 96%,25% 86%,14% 83%,12% 72%,2% 66%,5% 55%,0 45%,6% 36%,2% 26%,11% 20%,15% 9%,25% 10%,32% 2%,42% 6%);filter:drop-shadow(0 0 18px rgba(34,211,107,.12)) drop-shadow(0 18px 24px rgba(0,0,0,.48))}
      .csp-achievement-seal:before{content:"";position:absolute;inset:13px;border-radius:50%;background:#090d0b;box-shadow:inset 0 0 0 2px var(--ring)}
      .csp-achievement-seal:after{content:"";position:absolute;inset:28px;border:1px solid var(--ring);border-radius:50%;box-shadow:0 0 24px rgba(34,211,107,.16)}
      .csp-achievement-seal.silver{--m1:#dfe4e6;--m2:#687176;--m3:#fff;--ring:#adb6ba}.csp-achievement-seal.gold{--m1:#e4bd32;--m2:#765b08;--m3:#f6da69;--ring:#d0a91e}.csp-achievement-seal.platinum{--m1:#d9f1ea;--m2:#6f8580;--m3:#fff;--ring:#b7ddd1}
      .csp-achievement-symbol{position:absolute;inset:0;z-index:3;display:grid;place-items:center;font:900 39px/1 Inter,system-ui,sans-serif;color:#f7f7f4;text-shadow:0 2px 0 #000}
      .csp-achievement-top,.csp-achievement-tier{position:absolute;z-index:4;width:100%;left:0;text-align:center;font:800 8px/1 ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:.15em}.csp-achievement-top{top:30px;color:#aeb5b0}.csp-achievement-tier{bottom:30px;color:#22d36b;text-transform:uppercase}
      .csp-achievement-popup h2{font-size:24px;line-height:1.12;letter-spacing:-.03em;margin:10px 0 7px}.csp-achievement-popup p{max-width:340px;margin:0 auto;color:#929a95;font-size:13px;line-height:1.55}.csp-achievement-points{display:inline-flex;margin-top:14px;padding:7px 11px;border:1px solid rgba(212,168,67,.33);border-radius:999px;color:#f0c966;background:rgba(212,168,67,.08);font-size:11px;font-weight:900}
      .csp-achievement-actions{display:grid;grid-template-columns:1fr 1fr;gap:9px;margin-top:20px}.csp-achievement-actions button,.csp-achievement-actions a{min-height:44px;border-radius:10px;border:1px solid #2a302c;background:#151916;color:#e9ecea;font:800 12px/42px Inter,system-ui,sans-serif;text-decoration:none;cursor:pointer}.csp-achievement-actions a{background:#d4a843;border-color:#d4a843;color:#211806}.csp-achievement-close{position:absolute;right:13px;top:11px;width:32px;height:32px;border:0!important;background:transparent!important;color:#7d857f!important;font-size:22px!important;line-height:32px!important;padding:0!important}
      @keyframes cspAchFade{from{opacity:0}to{opacity:1}}@keyframes cspAchRise{from{opacity:0;transform:translateY(22px) scale(.96)}to{opacity:1;transform:none}}
      @media(max-width:480px){.csp-achievement-popup{padding:24px 17px 18px}.csp-achievement-actions{grid-template-columns:1fr}.csp-achievement-seal-wrap{height:155px}.csp-achievement-seal{width:138px;height:138px}}
    `;
    document.head.appendChild(s);
  }
  function next(){
    if(showing||!queue.length)return;
    showing=true;
    injectStyles();
    var a=parse(queue.shift());
    var overlay=document.createElement('div');
    overlay.className='csp-achievement-overlay';
    overlay.innerHTML=`<section class="csp-achievement-popup" role="dialog" aria-modal="true" aria-label="Achievement odomknutý">
      <button class="csp-achievement-close" type="button" aria-label="Zavrieť">×</button>
      <div class="csp-achievement-kicker">Achievement unlocked</div>
      <div class="csp-achievement-seal-wrap"><div class="csp-achievement-seal ${esc(tierClass(a.tier))}"><span class="csp-achievement-top">CSP</span><span class="csp-achievement-symbol">${esc(a.symbol)}</span><span class="csp-achievement-tier">${esc(a.tier)}</span></div></div>
      <h2>${esc(a.title)}</h2>${a.description?`<p>${esc(a.description)}</p>`:''}${a.points?`<span class="csp-achievement-points">${esc(a.points)}</span>`:''}
      <div class="csp-achievement-actions"><button type="button" data-achievement-dismiss>Pokračovať</button><a href="${esc(a.url)}">Zobraziť achievement</a></div>
    </section>`;
    document.body.appendChild(overlay);
    function close(){overlay.remove();showing=false;setTimeout(next,80)}
    overlay.querySelector('.csp-achievement-close').onclick=close;
    overlay.querySelector('[data-achievement-dismiss]').onclick=close;
    overlay.addEventListener('click',function(e){if(e.target===overlay)close()});
  }
  function show(notification){
    if(!notification||notification.notification_type!=='achievement_unlocked')return;
    queue.push(notification);next();
  }
  async function bind(client){
    if(bound||!client)return;
    var r=await client.auth.getSession();
    var session=r&&r.data&&r.data.session;
    if(!session)return;
    bound=true;
    var uid=session.user.id;
    channel=client.channel('csp-achievement-unlocks-'+uid)
      .on('postgres_changes',{event:'INSERT',schema:'public',table:'notifications',filter:'recipient_id=eq.'+uid},function(payload){
        if(payload&&payload.new&&payload.new.notification_type==='achievement_unlocked')show(payload.new);
      }).subscribe();
  }
  global.cspAchievementUnlock={bind:bind,show:show};
})(window);
