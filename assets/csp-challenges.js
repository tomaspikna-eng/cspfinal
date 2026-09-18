"use strict";

(function(){
  const $=id=>document.getElementById(id);
  const state=$("pageState");
  const filters=[...document.querySelectorAll("[data-filter]")];
  let payload=null;
  let activeFilter="all";

  function node(tag,className,text){
    const item=document.createElement(tag);
    if(className)item.className=className;
    if(text!==undefined)item.textContent=text;
    return item;
  }

  function setText(id,value){const item=$(id);if(item)item.textContent=value??"";}
  function initials(value){return String(value||"Hráč").trim().split(/\s+/).slice(0,2).map(part=>part[0]||"").join("").toUpperCase()||"H";}
  function parseDate(value){const result=new Date(value);return Number.isNaN(result.getTime())?null:result;}
  function dateLabel(value){const result=parseDate(value);return result?new Intl.DateTimeFormat("sk-SK",{day:"numeric",month:"short",year:"numeric"}).format(result):"—";}
  function shortDate(value){const result=parseDate(value);return result?new Intl.DateTimeFormat("sk-SK",{day:"numeric",month:"short"}).format(result):"—";}
  function daysUntil(value){const result=parseDate(value);return result?Math.max(0,Math.ceil((result.getTime()-Date.now())/86400000)):0;}
  function dayWord(value){if(value===1)return "deň";if(value>1&&value<5)return "dni";return "dní";}
  function clamp(value){return Math.max(0,Math.min(100,Number(value)||0));}

  function setPageState(message,error=false){
    if(!state)return;
    state.hidden=false;
    state.textContent=message;
    state.style.color=error?"#ff7b84":"#929893";
  }

  function hidePageState(){if(state)state.hidden=true;}

  function toast(title,message,error=false){
    const root=$("toast");if(!root)return;
    setText("toastTitle",title);setText("toastMessage",message);
    root.classList.toggle("error",error);root.classList.add("show");
    window.clearTimeout(window.cspChallengeToast);
    window.cspChallengeToast=window.setTimeout(()=>root.classList.remove("show"),3400);
  }

  function badge(item){
    const root=node("div","badge");
    ["badge-shell","badge-inner","badge-green","badge-field"].forEach(name=>root.append(node("span",name)));
    root.append(node("span","badge-csp","CSP"),node("span","badge-symbol",item.badge_symbol||"CSP"),node("span","badge-year",item.badge_label||"CHALLENGE"));
    return root;
  }

  function tierLabel(item){
    const rarity={common:"Bežná výzva",rare:"Vzácna výzva",elite:"Elitná výzva"}[item.rarity]||"Výzva";
    const medal={silver:"Striebro",gold:"Zlato",platinum:"Platina"}[item.medal]||item.medal;
    return `${rarity} · ${medal}`;
  }

  function statusLabel(item){
    if(item.state==="completed")return `Splnené ${shortDate(item.completed_at)}`;
    if(item.state==="joined")return `${item.days_remaining} ${dayWord(Number(item.days_remaining)||0)} zostáva`;
    if(item.state==="upcoming")return `Začína ${shortDate(item.starts_at)}`;
    if(item.state==="closed")return "Vstup uzavretý";
    const days=daysUntil(item.join_deadline);
    return `${days} ${dayWord(days)} na vstup`;
  }

  function progressLabel(item){
    if(item.state==="completed")return "Dokončené";
    if(item.state==="joined")return "Aktívna výzva";
    if(item.state==="closed")return "Vstup uzavretý";
    if(item.state==="upcoming")return "Pripravuje sa";
    return "Pred pridaním";
  }

  function actionButton(item){
    const button=node("button","card-action");button.type="button";
    if(item.state==="available"){
      button.classList.add("join-button");button.textContent="Pridať sa k výzve";
      button.addEventListener("click",()=>joinChallenge(item,button));
    }else{
      button.disabled=true;
      button.textContent=item.state==="completed"?"Výzva splnená ✓":item.state==="joined"?"Pridané ✓":item.state==="upcoming"?"Ešte nezačala":"Vstup uzavretý";
    }
    return button;
  }

  function challengeCard(item){
    const stateName=String(item.state||"available");
    const card=node("article",`challenge-card ${item.medal||"silver"} ${stateName==="joined"?"joined":""} ${stateName==="completed"?"completed":""}`.trim());
    card.dataset.state=stateName;card.dataset.code=item.code||"";card.id=`challenge-${item.code}`;
    const top=node("div","card-top");top.append(badge(item),node("span","time-left",statusLabel(item)));
    const current=Math.max(0,Number(item.progress_value)||0),target=Math.max(1,Number(item.target_value)||1);
    const progress=node("div","card-progress"),copy=node("div","progress-copy"),bar=node("div","bar"),fill=node("i");
    copy.append(node("span","",progressLabel(item)),node("b","",`${Math.min(current,target)} / ${target} ${item.unit_label||""}`));
    fill.style.width=`${clamp(item.progress_percent)}%`;bar.append(fill);progress.append(copy,bar,actionButton(item));
    card.append(top,node("span","tier",tierLabel(item)),node("h3","",item.title||"Výzva"),node("p","",item.description||""),progress);
    return card;
  }

  function applyFilter(){
    document.querySelectorAll(".challenge-card[data-state]").forEach(card=>{
      card.hidden=activeFilter!=="all"&&card.dataset.state!==activeFilter;
    });
  }

  function renderSummary(data){
    const season=data.season||{},summary=data.summary||{};
    const total=Number(summary.total)||0,completed=Number(summary.completed)||0,percent=clamp(summary.completion_percent),remaining=Math.max(0,Number(summary.remaining)||0);
    setText("sideSeason",`SEZÓNA ${season.year||""}`);setText("sidePercent",`${percent} %`);setText("sideCompleted",`${completed} z ${total} výziev splnených`);
    setText("seasonProgressText",`${completed} / ${total}`);$("seasonProgressBar").style.width=`${percent}%`;
    setText("remainingCount",summary.perfect_season?"Splnené":`${remaining} zostáva`);
    setText("activeCount",Number(summary.active)||0);setText("completedCount",completed);setText("completedSeason",`v sezóne ${season.year||""}`);setText("successPercent",`${percent} %`);
    setText("perfectBadge",`${completed}/${total}`);setText("featuredYear",`SEASON ${season.year||""}`);setText("featuredProgress",`${completed} / ${total}`);setText("featuredPercent",`${percent} % dokončených výziev`);$("featuredBar").style.width=`${percent}%`;
    const featured=$("featuredSeason");if(featured)featured.dataset.year=String(season.year||"");
    setText("seasonDates",`${dateLabel(season.starts_at)} – ${dateLabel(season.reward_cutoff)}`);
    const days=daysUntil(season.reward_cutoff);setText("daysRemaining",`${days} ${dayWord(days)}`);
    setText("rewardCopy",summary.perfect_season?"Splnil si všetkých 20 hlavných výziev sezóny.":`Do uzávierky ${dateLabel(season.reward_cutoff)} môžeš dokončiť všetkých ${total} výziev.`);
  }

  function render(data){
    payload=data||{};renderSummary(payload);
    const root=$("challengeGrid");root.replaceChildren();
    const items=Array.isArray(payload.items)?payload.items:[];
    if(!items.length){root.append(node("div","empty","V tejto sezóne zatiaľ nie sú dostupné žiadne výzvy."));return}
    items.forEach(item=>root.append(challengeCard(item)));applyFilter();
    const requested=new URLSearchParams(location.search).get("challenge");
    if(requested)window.setTimeout(()=>document.getElementById(`challenge-${requested}`)?.scrollIntoView({behavior:"smooth",block:"center"}),100);
  }

  async function loadChallenges(showOverlay=false){
    const client=window.cspAuth?.client;if(!client)throw new Error("CSP prihlásenie nie je dostupné.");
    if(showOverlay)setPageState("Aktualizujem výzvy…");
    const {data,error}=await client.rpc("get_my_challenges");
    if(error)throw error;
    render(data||{});hidePageState();
  }

  async function joinChallenge(item,button){
    const client=window.cspAuth?.client;if(!client)return;
    button.disabled=true;button.textContent="Pridávam…";
    const {error}=await client.rpc("join_my_challenge",{p_challenge_id:item.id});
    if(error){
      button.disabled=false;button.textContent="Pridať sa k výzve";
      toast("Výzvu sa nepodarilo aktivovať",error.message||"Skús to znova.",true);return;
    }
    toast("Výzva bola aktivovaná","Odteraz sa do nej započítavajú tvoje oprávnené aktivity.");
    try{await loadChallenges(false)}catch(error){console.error("[challenges-refresh]",error)}
  }

  function bind(){
    filters.forEach(button=>button.addEventListener("click",()=>{
      activeFilter=button.dataset.filter||"all";
      filters.forEach(item=>item.classList.toggle("active",item===button));applyFilter();
    }));
    $("mobileMenu")?.addEventListener("click",()=>$("sidebar")?.classList.toggle("open"));
  }

  async function init(){
    bind();
    try{
      const client=window.cspAuth?.client;if(!client)throw new Error("CSP prihlásenie nie je dostupné.");
      const {data:userData,error:userError}=await client.auth.getUser();
      if(userError||!userData.user){location.replace("/login/?returnTo="+encodeURIComponent(location.pathname));return}
      const profilePromise=client.from("profiles").select("full_name,plan,avatar_url").eq("id",userData.user.id).single();
      const challengesPromise=client.rpc("get_my_challenges");
      const [profileResult,challengesResult]=await Promise.all([profilePromise,challengesPromise]);
      if(challengesResult.error){
        if(String(challengesResult.error.message||"").toLowerCase().includes("pro+ plan required")){location.replace("/upgrade/?required=pro_plus");return}
        throw challengesResult.error;
      }
      const profile=profileResult.data||{},name=profile.full_name||userData.user.email?.split("@")[0]||"Hráč";
      const plan=String(profile.plan||"free").toLowerCase()==="pro_plus"?"pro_plus":String(profile.plan||"free").toLowerCase()==="pro"?"pro":"free";
      document.querySelector(".shell")?.classList.add(`plan-${plan.replace("_","-")}`);
      const home=({free:"/FREE/",pro:"/PRO/",pro_plus:"/PRO+/"})[plan];
      document.querySelectorAll("[data-player-home]").forEach(link=>link.href=home);
      const routes={"/profil/turnaje/":home+"turnaje/","/profil/treningy/":home+"treningy/","/profil/rebricky/":home+"rebricky/","/profil/priatelia/":home+"priatelia/","/profil/achievements/":home+"achievements/","/profil/moj-profil/":home+"moj-profil/","/profil-pro-plus/vyzvy/":home+"vyzvy/"};
      document.querySelectorAll("a[href]").forEach(link=>{const next=routes[link.getAttribute("href")];if(next)link.href=next;});
      document.querySelectorAll("[data-create-feature]").forEach(link=>{if(plan==="pro_plus"){link.removeAttribute("aria-disabled");return}link.setAttribute("aria-disabled","true");link.addEventListener("click",event=>{event.preventDefault();location.href="/upgrade/?required=pro_plus";});});
      setText("userName",name);setText("userPlanLabel",plan==="pro_plus"?"PRO+ účet":plan.toUpperCase()+" účet");
      const avatar=document.getElementById("userAvatar");if(avatar){avatar.innerHTML=profile.avatar_url?`<img src="${profile.avatar_url}" alt="${name}">`:initials(name);}
      render(challengesResult.data||{});hidePageState();
    }catch(error){
      console.error("[csp-challenges]",error);setPageState(error.message||"Výzvy sa nepodarilo načítať.",true);
    }
  }

  window.addEventListener("DOMContentLoaded",init);
})();
