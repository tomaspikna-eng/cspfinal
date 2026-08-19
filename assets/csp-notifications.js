"use strict";
(function(global){
  const esc=v=>String(v??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
  const ago=iso=>{
    const t=new Date(iso).getTime(), d=Math.max(0,Date.now()-t);
    const m=Math.floor(d/60000);
    if(m<1)return"teraz";
    if(m<60)return`pred ${m} min`;
    const h=Math.floor(m/60); if(h<24)return`pred ${h} h`;
    const day=Math.floor(h/24); if(day<7)return`pred ${day} d`;
    return new Intl.DateTimeFormat("sk-SK",{day:"numeric",month:"short"}).format(new Date(iso));
  };
  const iconFor=type=>{
    if(type==="new_follower")return"👤";
    if(type==="followed_player_training")return"◎";
    if(type==="followed_player_match")return"⚔";
    if(type==="followed_player_tournament_result")return"🏆";
    if(type==="followed_entity_event")return"📅";
    if(type==="followed_entity_tournament")return"🏆";
    return"•";
  };

  function injectStyles(){
    if(document.getElementById("csp-notifications-style"))return;
    const style=document.createElement("style");
    style.id="csp-notifications-style";
    style.textContent=`
      .csp-notif-anchor{position:relative}
      .csp-notif-count{
        position:absolute;top:-5px;right:-6px;min-width:18px;height:18px;padding:0 5px;
        border-radius:999px;background:#d94f4f;color:#fff;font:700 10px/18px system-ui;text-align:center;
        box-shadow:0 0 0 2px #0d0d11
      }
      .csp-notif-count.hidden{display:none}
      .csp-notif-panel{
        position:fixed;z-index:10000;width:min(390px,calc(100vw - 24px));max-height:min(610px,calc(100vh - 90px));
        overflow:hidden;background:#0d0d11;border:1px solid rgba(255,255,255,.10);border-radius:15px;
        box-shadow:0 22px 70px rgba(0,0,0,.60);display:none;color:#f4f4f8
      }
      .csp-notif-panel.open{display:flex;flex-direction:column}
      .csp-notif-head{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:15px 16px;border-bottom:1px solid rgba(255,255,255,.07)}
      .csp-notif-head strong{font:800 15px system-ui}
      .csp-notif-readall{border:0;background:none;color:#d4a843;font:700 12px system-ui;cursor:pointer}
      .csp-notif-list{overflow:auto}
      .csp-notif-item{display:grid;grid-template-columns:36px 1fr;gap:10px;padding:12px 14px;border-bottom:1px solid rgba(255,255,255,.05);cursor:pointer}
      .csp-notif-item:hover{background:rgba(255,255,255,.035)}
      .csp-notif-item.unread{background:rgba(212,168,67,.055)}
      .csp-notif-icon{width:34px;height:34px;border-radius:9px;display:grid;place-items:center;background:rgba(212,168,67,.10);color:#d4a843;font-weight:800}
      .csp-notif-copy b{display:block;font:750 13px/1.35 system-ui;color:#f4f4f8}
      .csp-notif-copy p{margin:3px 0 0;font:500 12px/1.4 system-ui;color:#a8a8b8}
      .csp-notif-time{display:block;margin-top:5px;font:600 10px/1.2 monospace;color:#6f7480}
      .csp-notif-empty{padding:34px 18px;text-align:center;color:#7c8190;font:500 13px/1.5 system-ui}
    `;
    document.head.appendChild(style);
  }

  async function bind(options={}){
    const client=options.client||global.cspAuth?.client;
    const button=typeof options.button==="string"?document.querySelector(options.button):options.button||document.querySelector("[data-csp-notifications-button]");
    if(!client||!button)return null;

    injectStyles();
    button.classList.add("csp-notif-anchor");
    button.dataset.cspNotificationsButton="1";
    let badge=button.querySelector(".csp-notif-count");
    if(!badge){
      badge=document.createElement("span");
      badge.className="csp-notif-count hidden";
      button.appendChild(badge);
    }

    const panel=document.createElement("section");
    panel.className="csp-notif-panel";
    panel.innerHTML=`
      <div class="csp-notif-head">
        <strong>Notifikácie</strong>
        <button class="csp-notif-readall" type="button">Označiť všetko ako prečítané</button>
      </div>
      <div class="csp-notif-list"><div class="csp-notif-empty">Načítavam…</div></div>`;
    document.body.appendChild(panel);
    const list=panel.querySelector(".csp-notif-list");
    const readAll=panel.querySelector(".csp-notif-readall");

    const {data:{session}}=await client.auth.getSession();
    if(!session)return null;
    const uid=session.user.id;
    let rows=[];

    function placePanel(){
      const r=button.getBoundingClientRect();
      const width=Math.min(390,window.innerWidth-24);
      const left=Math.max(12,Math.min(window.innerWidth-width-12,r.right-width));
      const top=Math.min(window.innerHeight-80,r.bottom+8);
      panel.style.width=width+"px";
      panel.style.left=left+"px";
      panel.style.top=top+"px";
    }
    function render(){
      const unread=rows.filter(n=>!n.is_read).length;
      badge.textContent=unread>99?"99+":String(unread);
      badge.classList.toggle("hidden",unread===0);
      if(!rows.length){
        list.innerHTML='<div class="csp-notif-empty">Zatiaľ nemáš žiadne notifikácie.</div>';
        return;
      }
      list.innerHTML=rows.map(n=>`
        <article class="csp-notif-item ${n.is_read?"":"unread"}" data-id="${esc(n.id)}" data-url="${esc(n.action_url||"")}">
          <span class="csp-notif-icon">${iconFor(n.notification_type)}</span>
          <div class="csp-notif-copy">
            <b>${esc(n.title)}</b>
            ${n.body?`<p>${esc(n.body)}</p>`:""}
            <span class="csp-notif-time">${ago(n.created_at)}</span>
          </div>
        </article>`).join("");
      list.querySelectorAll(".csp-notif-item").forEach(item=>item.addEventListener("click",async()=>{
        const id=item.dataset.id,url=item.dataset.url;
        const row=rows.find(r=>r.id===id);
        if(row&&!row.is_read){
          row.is_read=true;render();
          await client.from("notifications").update({is_read:true,read_at:new Date().toISOString()}).eq("id",id);
        }
        if(url)location.href=url;
      }));
    }
    async function load(){
      const {data,error}=await client.from("notifications")
        .select("id,notification_type,entity_type,entity_id,title,body,is_read,created_at,action_url")
        .eq("recipient_id",uid)
        .order("created_at",{ascending:false})
        .limit(40);
      if(error){console.error("[csp-notifications]",error);return}
      rows=data||[];render();
    }

    button.addEventListener("click",e=>{
      e.preventDefault();e.stopPropagation();
      placePanel();panel.classList.toggle("open");
    });
    document.addEventListener("click",e=>{
      if(!panel.contains(e.target)&&!button.contains(e.target))panel.classList.remove("open");
    });
    window.addEventListener("resize",()=>{if(panel.classList.contains("open"))placePanel()});
    readAll.addEventListener("click",async()=>{
      const {error}=await client.rpc("mark_all_notifications_read");
      if(error){console.error("[csp-notifications] mark all",error);return}
      rows.forEach(r=>r.is_read=true);render();
    });

    await load();

    const channel=client.channel("csp-notifications-"+uid)
      .on("postgres_changes",{event:"INSERT",schema:"public",table:"notifications",filter:`recipient_id=eq.${uid}`},payload=>{
        rows=[payload.new,...rows.filter(r=>r.id!==payload.new.id)].slice(0,40);
        render();
        options.onNew?.(payload.new);
      })
      .subscribe();

    return {reload:load,destroy:()=>{client.removeChannel(channel);panel.remove()}};
  }

  global.cspNotifications={bind};
})(window);
