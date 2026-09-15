(function(global){
  'use strict';
  if(!/^\/turnament\/?$/.test(global.location.pathname)) return;

  function injectStyles(){
    if(document.getElementById('csp-completed-tournament-layout-css')) return;
    const style=document.createElement('style');
    style.id='csp-completed-tournament-layout-css';
    style.textContent=`
      #matchArea.csp-results-first>.final-standings{margin-top:0;margin-bottom:14px}
      #matchArea.csp-results-first>.completed-result-lead{margin:0 0 8px;font-family:var(--mono);font-size:.66rem;font-weight:800;letter-spacing:.1em;text-transform:uppercase;color:var(--green)}
      .completed-match-history{margin-top:14px;border:1px solid var(--line);border-radius:12px;background:var(--card-2);overflow:hidden}
      .completed-match-history summary{list-style:none;display:flex;align-items:center;justify-content:space-between;gap:12px;padding:14px 16px;cursor:pointer;font-size:.84rem;font-weight:800;color:var(--muted-2);user-select:none}
      .completed-match-history summary::-webkit-details-marker{display:none}
      .completed-match-history summary::after{content:'+';font-family:var(--mono);font-size:1.05rem;color:var(--gold)}
      .completed-match-history[open] summary::after{content:'−'}
      .completed-match-history summary:hover{color:var(--fg);background:rgba(255,255,255,.02)}
      .completed-match-history-body{border-top:1px solid var(--line);padding:16px;max-height:70vh;overflow:auto}
      @media(max-width:600px){.completed-match-history-body{padding:10px;max-height:68vh}.completed-match-history summary{padding:13px 14px}}
    `;
    document.head.appendChild(style);
  }

  function isCompleted(){
    const chip=document.querySelector('.status-chip');
    return !!chip && (chip.classList.contains('completed') || /completed|ukončen|dokončen/i.test(chip.textContent||''));
  }

  function apply(){
    const area=document.getElementById('matchArea');
    if(!area || !isCompleted() || area.dataset.resultsFirst==='1') return;

    injectStyles();

    let standing=area.querySelector(':scope > .final-standings');
    let rrLabel=null;
    let rrStanding=null;

    if(!standing){
      const direct=Array.from(area.children);
      rrStanding=direct.find(el=>el.classList?.contains('standings'))||null;
      if(rrStanding){
        const prev=rrStanding.previousElementSibling;
        if(prev?.classList.contains('branch-label')) rrLabel=prev;
      }
    }

    if(!standing && !rrStanding) return;

    const keep=new Set([standing,rrStanding,rrLabel].filter(Boolean));
    const historyNodes=Array.from(area.childNodes).filter(node=>!keep.has(node));
    const details=document.createElement('details');
    details.className='completed-match-history';
    const summary=document.createElement('summary');
    summary.textContent='Zápasy a priebeh turnaja';
    const body=document.createElement('div');
    body.className='completed-match-history-body';
    historyNodes.forEach(node=>body.appendChild(node));
    details.append(summary,body);

    area.replaceChildren();
    area.classList.add('csp-results-first');
    if(standing){
      area.appendChild(standing);
    }else{
      const lead=document.createElement('div');
      lead.className='completed-result-lead';
      lead.textContent='Konečný výsledok turnaja';
      area.appendChild(lead);
      if(rrLabel) area.appendChild(rrLabel);
      area.appendChild(rrStanding);
    }
    area.appendChild(details);
    area.dataset.resultsFirst='1';
  }

  let queued=false;
  function queueApply(){
    if(queued)return;
    queued=true;
    requestAnimationFrame(()=>{queued=false;apply();});
  }

  const observer=new MutationObserver(queueApply);
  observer.observe(document.documentElement,{childList:true,subtree:true});
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',queueApply,{once:true});
  else queueApply();
})(window);
