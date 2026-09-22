
(function(){
  'use strict';
  const nav=document.querySelector('.nav');
  const toggle=document.querySelector('.nav-toggle');
  if(toggle&&nav){toggle.addEventListener('click',()=>nav.classList.toggle('open'));}
  const body=document.body;
  const section=body.dataset.section;
  const slug=body.dataset.slug;
  if(!section||!slug||!window.cspAuth||!window.cspAuth.client) return;
  const map={riesenia:'solution',sporty:'sport',funkcie:'feature'};
  const dbSection=map[section]||section;
  window.cspAuth.client.from('public_marketing_pages')
    .select('section,slug,title,eyebrow,summary,intro,items,steps,audience,vision,cta_label,cta_href,meta_title,meta_description')
    .eq('section',dbSection).eq('slug',slug).eq('is_published',true).maybeSingle()
    .then(({data,error})=>{
      if(error||!data) return;
      if(data.meta_title) document.title=data.meta_title;
      const md=document.querySelector('meta[name="description"]'); if(md&&data.meta_description) md.content=data.meta_description;
      const title=document.querySelector('[data-page-title]'); if(title) title.textContent=data.title||title.textContent;
      const eyebrow=document.querySelector('[data-page-eyebrow]'); if(eyebrow&&data.eyebrow) eyebrow.textContent=data.eyebrow;
      const summary=document.querySelector('[data-page-summary]'); if(summary&&data.summary) summary.textContent=data.summary;
      const intro=document.querySelector('[data-page-intro]'); if(intro&&data.intro) intro.textContent=data.intro;
      const items=document.querySelector('[data-page-items]');
      if(items&&Array.isArray(data.items)) items.innerHTML=data.items.map(x=>'<div class="detail-item">'+escapeHtml(x)+'</div>').join('');
      const steps=document.querySelector('[data-page-steps]');
      if(steps&&Array.isArray(data.steps)&&data.steps.length){
        steps.innerHTML=data.steps.map((x,i)=>'<div class="detail-step"><b>'+String(i+1).padStart(2,'0')+'</b><span>'+escapeHtml(x)+'</span></div>').join('');
        const wrap=steps.closest('[data-steps-wrap]'); if(wrap) wrap.hidden=false;
      }
      const audience=document.querySelector('[data-page-audience]'); if(audience&&data.audience) audience.textContent=data.audience;
      const vision=document.querySelector('[data-page-vision]'); if(vision&&data.vision) vision.textContent=data.vision;
      const cta=document.querySelector('[data-page-cta]'); if(cta&&data.cta_label){cta.textContent=data.cta_label;cta.href=data.cta_href||'#';}
    });
  function escapeHtml(v){return String(v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
})();
