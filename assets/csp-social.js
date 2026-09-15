/* Connect Sports Pro — social pack: Like · Share · Follow */
(function(global){
  "use strict";

  function el(value){ return typeof value==="string" ? document.getElementById(value) : value; }
  function dbFrom(options){ return options?.client || global.cspAuth?.client || null; }

  async function getSession(db){
    if(!db?.auth?.getSession) return null;
    const {data}=await db.auth.getSession();
    return data?.session || null;
  }

  function loginRedirect(){
    const next=global.location.pathname+global.location.search+global.location.hash;
    global.location.href="/login/?returnTo="+encodeURIComponent(next);
  }

  async function copy(text){
    if(navigator.clipboard?.writeText && global.isSecureContext){
      await navigator.clipboard.writeText(text);
      return;
    }
    const area=document.createElement("textarea");
    area.value=text; area.readOnly=true;
    area.style.position="fixed"; area.style.opacity="0";
    document.body.appendChild(area); area.select();
    const ok=document.execCommand("copy");
    area.remove();
    if(!ok) throw new Error("copy failed");
  }

  async function share(options={}){
    const payload={
      title:options.title || document.title,
      text:options.text || "",
      url:options.url || global.location.href
    };
    if(navigator.share){
      try{
        await navigator.share(payload);
        return {shared:true,copied:false};
      }catch(error){
        if(error?.name==="AbortError") return {cancelled:true};
      }
    }
    await copy(payload.url);
    return {shared:false,copied:true};
  }

  const entityBindings=new WeakMap();

  async function bind(options={}){
    const db=dbFrom(options);
    const entityType=String(options.entityType||"").trim();
    const entityId=String(options.entityId||"").trim();
    const likeButton=el(options.likeButton);
    const likeCount=el(options.likeCount);
    const shareButton=el(options.shareButton);
    const bindingElement=likeButton || shareButton;

    if(!db || !entityType || !entityId) return null;

    entityBindings.get(bindingElement)?.destroy?.();

    let session=await getSession(db);
    let liked=false;
    let busy=false;
    let destroyed=false;

    function render(){
      if(!likeButton) return;
      likeButton.classList.toggle("liked",liked);
      likeButton.setAttribute("aria-pressed",String(liked));
    }

    async function load(){
      session=await getSession(db);

      const countQuery=db.from("social_reactions")
        .select("id",{count:"exact",head:true})
        .eq("entity_type",entityType)
        .eq("entity_id",entityId)
        .eq("reaction_type","like");

      const ownLikeQuery=session
        ? db.from("social_reactions").select("id")
            .eq("user_id",session.user.id)
            .eq("entity_type",entityType)
            .eq("entity_id",entityId)
            .eq("reaction_type","like")
            .maybeSingle()
        : Promise.resolve({data:null,error:null});

      const [likes,myLike]=await Promise.all([countQuery,ownLikeQuery]);
      if(likes.error) throw likes.error;
      if(myLike.error) throw myLike.error;

      liked=!!myLike.data;
      if(likeCount) likeCount.textContent=String(likes.count||0);
      render();
      return {liked,likes:likes.count||0};
    }

    async function toggleLike(){
      if(busy || destroyed) return;
      session=session || await getSession(db);
      if(!session){ loginRedirect(); return; }

      busy=true;
      if(likeButton) likeButton.disabled=true;
      try{
        const result=liked
          ? await db.from("social_reactions").delete()
              .eq("user_id",session.user.id)
              .eq("entity_type",entityType)
              .eq("entity_id",entityId)
              .eq("reaction_type","like")
          : await db.from("social_reactions").insert({
              user_id:session.user.id,
              entity_type:entityType,
              entity_id:entityId,
              reaction_type:"like"
            });
        if(result.error) throw result.error;
        await load();
      }catch(error){
        console.error("[csp-social] entity like:",error);
        options.onError?.(error);
      }finally{
        busy=false;
        if(likeButton) likeButton.disabled=false;
      }
    }

    async function shareEntity(){
      try{
        const result=await share({
          title:options.title || document.title,
          text:options.text || "",
          url:options.url || global.location.href
        });
        if(result?.copied) options.onCopied?.();
      }catch(error){
        console.error("[csp-social] entity share:",error);
        options.onError?.(error);
      }
    }

    function destroy(){
      destroyed=true;
      likeButton?.removeEventListener("click",toggleLike);
      shareButton?.removeEventListener("click",shareEntity);
      if(bindingElement && entityBindings.get(bindingElement)?.destroy===destroy){
        entityBindings.delete(bindingElement);
      }
    }

    likeButton?.addEventListener("click",toggleLike);
    shareButton?.addEventListener("click",shareEntity);

    const api={reload:load,toggleLike,destroy};
    if(bindingElement) entityBindings.set(bindingElement,api);

    try{
      await load();
      return api;
    }catch(error){
      destroy();
      throw error;
    }
  }

  async function bindProfilePack(options={}){
    const db=dbFrom(options);
    const profileId=String(options.profileId||"");
    const role=String(options.role||"").toLowerCase();
    const likeButton=el(options.likeButton);
    const likeCount=el(options.likeCount);
    const shareButton=el(options.shareButton);
    const followButton=el(options.followButton);
    const followCount=el(options.followCount);

    if(!db || !profileId) return null;

    let session=await getSession(db);
    let liked=false;
    let following=false;
    let busyLike=false;
    let busyFollow=false;

    const own=()=>!!session && session.user.id===profileId;
    const followable=()=>role!=="admin";

    function render(){
      const isOwn=own();
      if(likeButton){
        likeButton.classList.toggle("hidden",isOwn);
        likeButton.classList.toggle("liked",liked);
        likeButton.setAttribute("aria-pressed",String(liked));
      }
      if(followButton){
        followButton.classList.toggle("hidden",isOwn || !followable());
        followButton.classList.toggle("following",following);
        followButton.setAttribute("aria-pressed",String(following));
        const label=followButton.querySelector("[data-follow-label]");
        if(label) label.textContent=following ? "Following" : "+ Follow";
      }
    }

    async function load(){
      session=await getSession(db);

      const likeCountQuery=db.from("social_reactions")
        .select("id",{count:"exact",head:true})
        .eq("entity_type","profile")
        .eq("entity_id",profileId)
        .eq("reaction_type","like");

      const followCountQuery=db.from("profile_follows")
        .select("following_profile_id",{count:"exact",head:true})
        .eq("following_profile_id",profileId);

      const ownLikeQuery=session && !own()
        ? db.from("social_reactions").select("id")
            .eq("user_id",session.user.id)
            .eq("entity_type","profile")
            .eq("entity_id",profileId)
            .eq("reaction_type","like")
            .maybeSingle()
        : Promise.resolve({data:null,error:null});

      const ownFollowQuery=session && !own() && followable()
        ? db.from("profile_follows").select("following_profile_id")
            .eq("follower_id",session.user.id)
            .eq("following_profile_id",profileId)
            .maybeSingle()
        : Promise.resolve({data:null,error:null});

      const [likes,followers,myLike,myFollow]=await Promise.all([
        likeCountQuery,followCountQuery,ownLikeQuery,ownFollowQuery
      ]);
      if(likes.error) throw likes.error;
      if(followers.error) throw followers.error;
      if(myLike.error) throw myLike.error;
      if(myFollow.error) throw myFollow.error;

      liked=!!myLike.data;
      following=!!myFollow.data;
      if(likeCount) likeCount.textContent=String(likes.count||0);
      if(followCount) followCount.textContent=String(followers.count||0);
      render();
      return {liked,following,likes:likes.count||0,followers:followers.count||0};
    }

    async function toggleLike(){
      if(busyLike) return;
      session=session || await getSession(db);
      if(!session){ loginRedirect(); return; }
      if(own()) return;
      busyLike=true;
      if(likeButton) likeButton.disabled=true;
      try{
        const result=liked
          ? await db.from("social_reactions").delete()
              .eq("user_id",session.user.id)
              .eq("entity_type","profile")
              .eq("entity_id",profileId)
              .eq("reaction_type","like")
          : await db.from("social_reactions").insert({
              user_id:session.user.id,
              entity_type:"profile",
              entity_id:profileId,
              reaction_type:"like"
            });
        if(result.error) throw result.error;
        await load();
      }catch(error){
        console.error("[csp-social] profile like:",error);
        options.onError?.(error);
      }finally{
        busyLike=false;
        if(likeButton) likeButton.disabled=false;
      }
    }

    async function toggleFollow(){
      if(busyFollow || !followable()) return;
      session=session || await getSession(db);
      if(!session){ loginRedirect(); return; }
      if(own()) return;
      busyFollow=true;
      if(followButton) followButton.disabled=true;
      try{
        const result=following
          ? await db.from("profile_follows").delete()
              .eq("follower_id",session.user.id)
              .eq("following_profile_id",profileId)
          : await db.from("profile_follows").insert({
              follower_id:session.user.id,
              following_profile_id:profileId
            });
        if(result.error) throw result.error;
        await load();
      }catch(error){
        console.error("[csp-social] profile follow:",error);
        options.onError?.(error);
      }finally{
        busyFollow=false;
        if(followButton) followButton.disabled=false;
      }
    }

    likeButton?.addEventListener("click",toggleLike);
    followButton?.addEventListener("click",toggleFollow);
    shareButton?.addEventListener("click",async()=>{
      try{
        const result=await share({
          title:options.title || document.title,
          text:options.text || "",
          url:options.url || global.location.href
        });
        if(result?.copied) options.onCopied?.();
      }catch(error){
        console.error("[csp-social] profile share:",error);
        options.onError?.(error);
      }
    });

    await load();
    return {reload:load,toggleLike,toggleFollow};
  }

  global.cspSocial={...(global.cspSocial||{}),share,bind,bindProfilePack};
})(window);

/* CSP player profile achievement summary */
(function(global){
  "use strict";
  if(!/^\/profil\/?$/.test(global.location.pathname)) return;

  const URL="https://lcmoykaqvvfybtobhtqg.supabase.co";
  const KEY="sb_publishable_h3_yK3K_GUahLdz13dDWDg_PzxGE6xR";
  const badgeLabels={first_step:"01",first_match:"▶",first_win:"V",first_tournament:"T",first_training:"TR",matches_10:"10",matches_25:"25",matches_50:"50",matches_100:"100",wins_5:"5V",wins_10:"10V",wins_50:"50V",wins_100:"100V",win_streak_3:"3×",win_streak_5:"5×",win_streak_10:"10×",group_winner:"G1",top_8:"TOP8",semifinal:"SF",finalist:"F",champion:"1",clean_tournament:"0L",champion_2:"2×",champion_5:"5×",tournaments_10:"10T"};
  const esc=value=>String(value??"").replace(/[&<>"']/g,ch=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[ch]));

  function injectStyles(){
    if(document.getElementById("csp-profile-achievement-style")) return;
    const style=document.createElement("style");
    style.id="csp-profile-achievement-style";
    style.textContent=`
      .profile-achievement-panel{margin-top:8px;border:1px solid rgba(212,168,67,.28);border-radius:10px;background:linear-gradient(145deg,rgba(212,168,67,.08),#0d0f0e 55%);padding:18px;display:grid;gap:15px}
      .profile-achievement-head{display:flex;align-items:center;justify-content:space-between;gap:14px}.profile-achievement-head span{font-size:8px;letter-spacing:.17em;color:#d4a843;font-weight:850}.profile-achievement-head h2{font-size:15px;margin:5px 0 0}.profile-achievement-link{font-size:9px;font-weight:800;color:#f0c966;border:1px solid rgba(212,168,67,.35);padding:8px 10px;border-radius:7px}
      .profile-achievement-stats{display:flex;align-items:baseline;gap:18px}.profile-achievement-stats strong{font-size:30px;color:#f0c966;letter-spacing:-.04em}.profile-achievement-stats b{font-size:11px}.profile-achievement-stats small{display:block;color:#8f958f;font-size:8px;margin-top:2px}
      .profile-achievement-badges{display:grid;grid-template-columns:repeat(6,minmax(0,1fr));gap:7px}.profile-achievement-badge{min-width:0;border:1px solid #252925;border-radius:8px;background:#121513;padding:9px;display:flex;align-items:center;gap:8px}.profile-achievement-badge i{width:32px;height:32px;flex:0 0 32px;border-radius:50%;display:grid;place-items:center;border:1px solid rgba(212,168,67,.55);color:#f0c966;font-style:normal;font-size:8px;font-weight:900;background:rgba(212,168,67,.08)}.profile-achievement-badge div{min-width:0}.profile-achievement-badge b{display:block;font-size:9px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.profile-achievement-badge small{display:block;font-size:7px;color:#8f958f;margin-top:3px}.profile-achievement-empty{font-size:10px;color:#8f958f}
      @media(max-width:900px){.profile-achievement-badges{grid-template-columns:repeat(3,minmax(0,1fr))}}@media(max-width:560px){.profile-achievement-head{align-items:flex-start}.profile-achievement-badges{grid-template-columns:repeat(2,minmax(0,1fr))}.profile-achievement-stats{gap:12px}}
    `;
    document.head.appendChild(style);
  }

  function waitForTarget(){
    return new Promise(resolve=>{
      const find=()=>document.querySelector(".metrics")||document.querySelector(".player-header");
      const now=find(); if(now){resolve(now);return;}
      const observer=new MutationObserver(()=>{const found=find();if(found){observer.disconnect();resolve(found);}});
      observer.observe(document.documentElement,{childList:true,subtree:true});
      setTimeout(()=>{observer.disconnect();resolve(find());},12000);
    });
  }

  function render(target,payload,publicView){
    if(!target||document.getElementById("profile-achievement-summary")) return;
    injectStyles();
    const summary=payload?.summary||{};
    const items=Array.isArray(payload?.items)?payload.items:[];
    const unlocked=items.filter(x=>x.unlocked).sort((a,b)=>(Number(b.points)||0)-(Number(a.points)||0)).slice(0,6);
    const panel=document.createElement("section");
    panel.id="profile-achievement-summary";
    panel.className="profile-achievement-panel";
    const detailsHref=publicView?"#":"/profil/achievements/";
    panel.innerHTML=`<div class="profile-achievement-head"><div><span>GLOBAL CORE SERIES 01</span><h2>Achievements</h2></div>${publicView?"":`<a class="profile-achievement-link" href="${detailsHref}">Všetky achievementy →</a>`}</div><div class="profile-achievement-stats"><div><strong>${Number(summary.points)||0}</strong><small>ACHIEVEMENT BODOV</small></div><div><b>${Number(summary.unlocked)||0} / ${Number(summary.total)||25}</b><small>ODOMKNUTÉ</small></div></div><div class="profile-achievement-badges">${unlocked.length?unlocked.map(item=>`<div class="profile-achievement-badge"><i>${esc(badgeLabels[item.code]||"CSP")}</i><div><b>${esc(item.name)}</b><small>+${Number(item.points)||0} B</small></div></div>`).join(""):'<div class="profile-achievement-empty">Zatiaľ bez odomknutých achievementov.</div>'}</div>`;
    if(target.classList.contains("metrics")) target.insertAdjacentElement("afterend",panel); else target.insertAdjacentElement("afterend",panel);
  }

  async function init(){
    try{
      if(!global.supabase) return;
      const client=global.supabase.createClient(URL,KEY,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
      const params=new URLSearchParams(global.location.search);
      const requestedId=params.get("id");
      const publicView=params.get("view")==="public"&&!!requestedId;
      let result;
      if(publicView){
        result=await client.rpc("get_profile_achievements",{p_user_id:requestedId});
      }else{
        const {data:userData}=await client.auth.getUser();
        if(!userData?.user) return;
        result=await client.rpc("get_my_achievements");
      }
      if(result.error) throw result.error;
      const target=await waitForTarget();
      render(target,result.data||{},publicView);
    }catch(error){
      console.warn("[csp-achievements-profile]",error);
    }
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded",init,{once:true}); else init();
})(window);
