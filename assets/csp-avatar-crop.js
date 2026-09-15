(function(global){
  "use strict";

  const SUPABASE_URL="https://lcmoykaqvvfybtobhtqg.supabase.co";
  const SUPABASE_KEY="sb_publishable_h3_yK3K_GUahLdz13dDWDg_PzxGE6xR";
  const db=global.cspAuth?.client || (global.supabase?.createClient ? global.supabase.createClient(SUPABASE_URL,SUPABASE_KEY,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}}) : null);
  if(!db)return;

  const clamp=(value,min,max)=>Math.min(max,Math.max(min,value));
  const state={profileId:null,x:50,y:50,zoom:1,file:null,objectUrl:null,avatarUrl:null};

  function styleAvatarImages(){
    const selectors=["#avatar img","#avatarPreview img",".public-avatar img","[data-achievement-avatar] img",".mini-avatar img"];
    document.querySelectorAll(selectors.join(",")).forEach(img=>{
      img.style.objectFit="cover";
      img.style.objectPosition=`${state.x}% ${state.y}%`;
      img.style.transform=`scale(${state.zoom})`;
      img.style.transformOrigin="center center";
    });
  }

  async function resolveProfileId(){
    const params=new URLSearchParams(location.search);
    const requested=params.get("id");
    if(requested)return requested;
    const {data}=await db.auth.getUser();
    return data?.user?.id||null;
  }

  async function loadCropState(){
    try{
      state.profileId=await resolveProfileId();
      if(!state.profileId)return;
      const {data,error}=await db.from("profiles")
        .select("avatar_url,avatar_position_x,avatar_position_y,avatar_zoom")
        .eq("id",state.profileId).maybeSingle();
      if(error||!data)return;
      state.avatarUrl=data.avatar_url||null;
      state.x=clamp(Number(data.avatar_position_x)||50,0,100);
      state.y=clamp(Number(data.avatar_position_y)||50,0,100);
      state.zoom=clamp(Number(data.avatar_zoom)||1,1,3);
      styleAvatarImages();
    }catch(error){
      console.warn("[avatar-crop] load",error);
    }
  }

  function ensureStyle(){
    if(document.getElementById("csp-avatar-crop-style"))return;
    const style=document.createElement("style");
    style.id="csp-avatar-crop-style";
    style.textContent=`
      .csp-avatar-modal{position:fixed;inset:0;z-index:5000;display:grid;place-items:center;padding:16px;background:rgba(0,0,0,.78);backdrop-filter:blur(8px)}
      .csp-avatar-card{width:min(520px,100%);border:1px solid #343934;border-radius:16px;background:#0d0f0e;box-shadow:0 28px 90px rgba(0,0,0,.55);padding:18px}
      .csp-avatar-head{display:flex;align-items:flex-start;justify-content:space-between;gap:16px;margin-bottom:15px}.csp-avatar-head span{font-size:8px;letter-spacing:.16em;color:#d4a843;font-weight:900}.csp-avatar-head h2{margin:4px 0 0;font-size:20px}.csp-avatar-close{width:36px;height:36px;border:1px solid #343934;border-radius:9px;background:#151815;color:#fff;font-size:20px}
      .csp-avatar-stage{width:min(340px,76vw);aspect-ratio:1;margin:0 auto;border-radius:50%;overflow:hidden;position:relative;background:#080a09;border:2px solid rgba(212,168,67,.55);touch-action:none;cursor:grab}.csp-avatar-stage:active{cursor:grabbing}.csp-avatar-stage img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;user-select:none;pointer-events:none}
      .csp-avatar-guide{position:absolute;inset:0;border-radius:50%;box-shadow:inset 0 0 0 1px rgba(255,255,255,.12);pointer-events:none}.csp-avatar-guide:before,.csp-avatar-guide:after{content:"";position:absolute;background:rgba(255,255,255,.11)}.csp-avatar-guide:before{left:50%;top:0;bottom:0;width:1px}.csp-avatar-guide:after{top:50%;left:0;right:0;height:1px}
      .csp-avatar-controls{display:grid;gap:8px;margin-top:16px}.csp-avatar-controls label{font-size:9px;color:#8f958f;font-weight:800;letter-spacing:.08em}.csp-avatar-controls input[type=range]{width:100%;accent-color:#d4a843}
      .csp-avatar-actions{display:flex;justify-content:flex-end;gap:8px;margin-top:17px}.csp-avatar-actions button{min-height:42px;padding:0 14px;border-radius:9px;border:1px solid #343934;background:#151815;color:#eee;font-size:12px;font-weight:800}.csp-avatar-actions .primary{background:#d4a843;border-color:#d4a843;color:#211806}.csp-avatar-actions button:disabled{opacity:.55}
      .csp-avatar-edit-btn{min-height:42px;padding:0 14px;border-radius:9px;border:1px solid #343934;background:#151815;color:#eee;font-size:12px;font-weight:800;cursor:pointer}
      @media(max-width:520px){.csp-avatar-card{padding:14px}.csp-avatar-stage{width:min(300px,78vw)}}
    `;
    document.head.appendChild(style);
  }

  function currentSource(){return state.file&&state.objectUrl?state.objectUrl:state.avatarUrl;}

  function openEditor({file=null}={}){
    ensureStyle();
    if(file){
      if(state.objectUrl)URL.revokeObjectURL(state.objectUrl);
      state.file=file;
      state.objectUrl=URL.createObjectURL(file);
      state.x=50;state.y=50;state.zoom=1;
    }else{
      state.file=null;
      if(state.objectUrl){URL.revokeObjectURL(state.objectUrl);state.objectUrl=null;}
    }
    const src=currentSource();
    if(!src)return;
    document.getElementById("csp-avatar-modal")?.remove();
    const modal=document.createElement("div");
    modal.id="csp-avatar-modal";modal.className="csp-avatar-modal";
    modal.innerHTML=`<div class="csp-avatar-card" role="dialog" aria-modal="true" aria-labelledby="csp-avatar-title">
      <div class="csp-avatar-head"><div><span>PROFILOVÁ FOTOGRAFIA</span><h2 id="csp-avatar-title">Nastaviť výrez</h2></div><button class="csp-avatar-close" type="button" aria-label="Zavrieť">×</button></div>
      <div class="csp-avatar-stage"><img alt="Náhľad profilovej fotografie"><div class="csp-avatar-guide"></div></div>
      <div class="csp-avatar-controls"><label for="csp-avatar-zoom">PRIBLÍŽENIE</label><input id="csp-avatar-zoom" type="range" min="1" max="3" step="0.01" value="${state.zoom}"></div>
      <div class="csp-avatar-actions"><button type="button" data-reset>Reset</button><button type="button" data-cancel>Zrušiť</button><button type="button" class="primary" data-save>Uložiť pozíciu</button></div>
    </div>`;
    document.body.appendChild(modal);
    const stage=modal.querySelector(".csp-avatar-stage"),img=stage.querySelector("img"),zoom=modal.querySelector("#csp-avatar-zoom"),save=modal.querySelector("[data-save]");
    img.src=src;
    const render=()=>{img.style.objectPosition=`${state.x}% ${state.y}%`;img.style.transform=`scale(${state.zoom})`;img.style.transformOrigin="center center";zoom.value=String(state.zoom)};
    render();
    let dragging=false,lastX=0,lastY=0;
    const down=e=>{dragging=true;lastX=e.clientX;lastY=e.clientY;stage.setPointerCapture?.(e.pointerId)};
    const move=e=>{if(!dragging)return;const r=stage.getBoundingClientRect();const dx=e.clientX-lastX,dy=e.clientY-lastY;lastX=e.clientX;lastY=e.clientY;state.x=clamp(state.x-(dx/r.width)*100/state.zoom,0,100);state.y=clamp(state.y-(dy/r.height)*100/state.zoom,0,100);render()};
    const up=()=>{dragging=false};
    stage.addEventListener("pointerdown",down);stage.addEventListener("pointermove",move);stage.addEventListener("pointerup",up);stage.addEventListener("pointercancel",up);
    zoom.addEventListener("input",()=>{state.zoom=clamp(Number(zoom.value)||1,1,3);render()});
    modal.querySelector("[data-reset]").addEventListener("click",()=>{state.x=50;state.y=50;state.zoom=1;render()});
    const close=()=>{modal.remove();if(state.objectUrl&&!state.file){URL.revokeObjectURL(state.objectUrl);state.objectUrl=null;}};
    modal.querySelector(".csp-avatar-close").addEventListener("click",close);modal.querySelector("[data-cancel]").addEventListener("click",close);modal.addEventListener("click",e=>{if(e.target===modal)close()});
    save.addEventListener("click",async()=>{
      save.disabled=true;save.textContent="Ukladám…";
      try{
        let avatarUrl=state.avatarUrl;
        if(state.file){
          const ext=(state.file.name.split(".").pop()||"jpg").toLowerCase().replace("jpeg","jpg");
          const storagePath=`${state.profileId}/avatar-profile.${ext}`;
          const {error:uploadError}=await db.storage.from("avatars").upload(storagePath,state.file,{cacheControl:"3600",upsert:true,contentType:state.file.type});
          if(uploadError)throw uploadError;
          const {data:urlData}=db.storage.from("avatars").getPublicUrl(storagePath);
          avatarUrl=urlData?.publicUrl||null;
          if(!avatarUrl)throw new Error("Avatar URL unavailable");
        }
        const {error:updateError}=await db.from("profiles").update({avatar_url:avatarUrl,avatar_position_x:state.x,avatar_position_y:state.y,avatar_zoom:state.zoom}).eq("id",state.profileId);
        if(updateError)throw updateError;
        state.avatarUrl=avatarUrl;
        document.querySelectorAll("#avatarPreview,#avatar,.public-avatar,[data-achievement-avatar]").forEach(root=>{
          let target=root.querySelector("img");
          if(!target&&avatarUrl){target=new Image();target.alt="Profilová fotografia";root.replaceChildren(target)}
          if(target&&avatarUrl){target.src=avatarUrl+"?v="+Date.now();}
        });
        styleAvatarImages();
        state.file=null;
        if(state.objectUrl){URL.revokeObjectURL(state.objectUrl);state.objectUrl=null;}
        modal.remove();
        const toast=document.getElementById("toast");
        if(toast){toast.textContent="Profilová fotografia bola uložená.";toast.className="toast ok";setTimeout(()=>toast.classList.add("hidden"),2800)}
      }catch(error){
        console.error("[avatar-crop] save",error);save.disabled=false;save.textContent="Uložiť pozíciu";
      }
    });
  }

  function bindEditor(){
    const input=document.getElementById("avatarInput"),button=document.getElementById("avatarButton");
    if(!input||!button)return;
    input.addEventListener("change",event=>{
      const file=input.files?.[0];
      if(!file)return;
      if(!["image/jpeg","image/png","image/webp"].includes(file.type)||file.size>8*1024*1024)return;
      event.stopImmediatePropagation();
      openEditor({file});
      setTimeout(()=>{input.value=""},0);
    },true);
    if(!document.getElementById("avatarCropButton")){
      const edit=document.createElement("button");edit.type="button";edit.id="avatarCropButton";edit.className="csp-avatar-edit-btn";edit.textContent="Upraviť výrez";
      edit.addEventListener("click",()=>openEditor());
      button.insertAdjacentElement("afterend",edit);
    }
  }

  const observer=new MutationObserver(()=>styleAvatarImages());
  observer.observe(document.documentElement,{childList:true,subtree:true});
  const start=async()=>{await loadCropState();bindEditor();styleAvatarImages()};
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",start,{once:true});else start();
})(window);
