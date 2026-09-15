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
  const badgeLabels={first_step:"01",first_match:"▶",first_win:"V",first_tournament:"T",first_training:"TR",matches_10:"10",matches_25:"25",matches_50:"50",matches_100:"100",wins_5:"5V",wins_10:"10V",wins_50:"50V",wins_100:"100V",win_streak_3:"3×",win_streak_5:"5×",win_streak_10:"10×",group_winner:"G1",top_8:"TOP8",semifinal:"SF",finalist:"F",champion:"1",clean_tournament:"0L",champion_2:"2×",champion_5:"5×",tournaments_10:"10T",darts_180_1:"180",darts_180_10:"10×",darts_180_50:"50×",darts_180_100:"100×",darts_checkout_100:"100+",darts_checkout_120:"120+",darts_checkout_150:"150+",darts_streak_100x3:"3×100",darts_streak_140x3:"3×140"};
  const esc=value=>String(value??"").replace(/[&<>"']/g,ch=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[ch]));

  function injectStyles(){
    if(document.getElementById("csp-profile-achievement-style")) return;
    const style=document.createElement("style");
    style.id="csp-profile-achievement-style";
    style.textContent=`
      .profile-achievement-panel{margin-top:8px;border:1px solid rgba(212,168,67,.28);border-radius:10px;background:linear-gradient(145deg,rgba(212,168,67,.07),#0d0f0e 55%);padding:18px;display:grid;gap:15px}
      .profile-achievement-head{display:flex;align-items:center;justify-content:space-between;gap:14px}.profile-achievement-head span{font-size:8px;letter-spacing:.17em;color:#d4a843;font-weight:850}.profile-achievement-head h2{font-size:15px;margin:5px 0 0}.profile-achievement-link{font-size:9px;font-weight:800;color:#f0c966;border:1px solid rgba(212,168,67,.35);padding:8px 10px;border-radius:7px}
      .profile-achievement-stats{display:flex;align-items:baseline;gap:18px}.profile-achievement-stats strong{font-size:30px;color:#f0c966;letter-spacing:-.04em}.profile-achievement-stats b{font-size:11px}.profile-achievement-stats small{display:block;color:#8f958f;font-size:8px;margin-top:2px}
      .profile-achievement-badges{display:grid;grid-template-columns:repeat(6,minmax(0,1fr));gap:8px}.profile-achievement-badge{--seal-a:#e4bd32;--seal-b:#765b08;--seal-c:#f6da69;--seal-ring:#d0a91e;min-width:0;border:1px solid #252925;border-radius:10px;background:#111412;padding:10px 8px;display:grid;grid-template-columns:60px minmax(0,1fr);align-items:center;gap:9px;overflow:hidden}.profile-achievement-badge.bronze{--seal-a:#c8864a;--seal-b:#5d3420;--seal-c:#e3a970;--seal-ring:#a86c3a}.profile-achievement-badge.silver{--seal-a:#dfe4e6;--seal-b:#687176;--seal-c:#fff;--seal-ring:#adb6ba}.profile-achievement-badge.gold{--seal-a:#e4bd32;--seal-b:#765b08;--seal-c:#f6da69;--seal-ring:#d0a91e}.profile-achievement-badge.platinum{--seal-a:#d9f1ea;--seal-b:#6f8580;--seal-c:#fff;--seal-ring:#b7ddd1}
      .profile-achievement-seal{width:60px;height:60px;position:relative;display:block;color:#f4f6f5;background:conic-gradient(from 0deg,var(--seal-a),var(--seal-b),var(--seal-c),var(--seal-b),var(--seal-a));clip-path:polygon(50% 0,58% 6%,68% 2%,75% 10%,85% 9%,90% 19%,98% 25%,94% 36%,100% 45%,95% 54%,98% 65%,89% 72%,86% 82%,75% 84%,68% 95%,58% 92%,50% 100%,41% 93%,31% 96%,25% 86%,14% 83%,12% 72%,2% 66%,5% 55%,0 45%,6% 36%,2% 26%,11% 20%,15% 9%,25% 10%,32% 2%,42% 6%);filter:drop-shadow(0 7px 9px rgba(0,0,0,.42))}.profile-achievement-seal:before{content:"";position:absolute;inset:5px;border-radius:50%;background:linear-gradient(160deg,#111713,#070a08 72%);box-shadow:inset 0 0 0 1.2px var(--seal-ring),0 0 10px rgba(34,211,107,.08);z-index:1}.profile-achievement-seal-ring{position:absolute;inset:11px;border:1px solid var(--seal-ring);border-radius:50%;z-index:2;box-shadow:0 0 11px rgba(34,211,107,.15)}.profile-achievement-seal-top,.profile-achievement-seal-meta,.profile-achievement-seal-symbol{position:absolute;left:0;width:100%;text-align:center;z-index:3}.profile-achievement-seal-top{top:10px;font-size:4px;line-height:1;font-weight:900;letter-spacing:.17em;color:#aab1ad}.profile-achievement-seal-symbol{top:50%;transform:translateY(-55%);font-size:13px;line-height:1;font-weight:950;letter-spacing:-.05em;color:#fff;text-shadow:0 2px 2px rgba(0,0,0,.55);padding:0 7px}.profile-achievement-seal-meta{bottom:9px;font-size:3.8px;line-height:1;font-weight:900;letter-spacing:.12em;color:#22d36b}.profile-achievement-copy{min-width:0}.profile-achievement-badge b{display:block;font-size:9px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.profile-achievement-badge small{display:block;font-size:7px;color:#8f958f;margin-top:4px}.profile-achievement-empty{font-size:10px;color:#8f958f}
      @media(max-width:1100px){.profile-achievement-badges{grid-template-columns:repeat(3,minmax(0,1fr))}}@media(max-width:620px){.profile-achievement-head{align-items:flex-start}.profile-achievement-badges{grid-template-columns:repeat(2,minmax(0,1fr))}.profile-achievement-stats{gap:12px}.profile-achievement-badge{grid-template-columns:54px minmax(0,1fr)}.profile-achievement-seal{width:54px;height:54px}.profile-achievement-seal-ring{inset:10px}.profile-achievement-seal-top{top:9px}.profile-achievement-seal-meta{bottom:8px}}
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
    const cards=unlocked.length?unlocked.map(item=>{
      const rarity=["bronze","silver","gold","platinum"].includes(String(item.rarity||"").toLowerCase())?String(item.rarity).toLowerCase():"gold";
      return `<div class="profile-achievement-badge ${rarity}"><span class="profile-achievement-seal" aria-label="${esc(item.name)}"><span class="profile-achievement-seal-ring"></span><span class="profile-achievement-seal-top">CSP</span><span class="profile-achievement-seal-symbol">${esc(badgeLabels[item.code]||"CSP")}</span><span class="profile-achievement-seal-meta">EARNED</span></span><div class="profile-achievement-copy"><b>${esc(item.name)}</b><small>+${Number(item.points)||0} B · ${rarity.toUpperCase()}</small></div></div>`;
    }).join(""):'<div class="profile-achievement-empty">Zatiaľ bez odomknutých achievementov.</div>';
    panel.innerHTML=`<div class="profile-achievement-head"><div><span>GLOBAL CORE SERIES 01</span><h2>Achievements</h2></div>${publicView?"":`<a class="profile-achievement-link" href="${detailsHref}">Všetky achievementy →</a>`}</div><div class="profile-achievement-stats"><div><strong>${Number(summary.points)||0}</strong><small>ACHIEVEMENT BODOV</small></div><div><b>${Number(summary.unlocked)||0} / ${Number(summary.total)||items.length}</b><small>ODOMKNUTÉ</small></div></div><div class="profile-achievement-badges">${cards}</div>`;
    target.insertAdjacentElement("afterend",panel);
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
