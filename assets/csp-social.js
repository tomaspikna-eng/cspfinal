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
