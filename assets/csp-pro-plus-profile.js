"use strict";

(function(){
  const $=id=>document.getElementById(id);
  const state=$("pageState");
  const query=new URLSearchParams(location.search);
  const publicPlayerId=query.get("id");
  const isPublicView=query.get("view")==="public"&&Boolean(publicPlayerId);
  let dashboard=null;
  let currentPlan="free";

  function text(id,value){const node=$(id);if(node)node.textContent=value??"";}
  function initials(name){return String(name||"Hráč").trim().split(/\s+/).slice(0,2).map(part=>part[0]||"").join("").toUpperCase();}
  function countryFlag(code){
    const value=String(code||"").trim().toUpperCase();
    return /^[A-Z]{2}$/.test(value)?String.fromCodePoint(...[...value].map(letter=>127397+letter.charCodeAt(0))):"";
  }
  function countryName(code){
    const value=String(code||"").trim().toUpperCase();
    if(!/^[A-Z]{2}$/.test(value))return "";
    try{return new Intl.DisplayNames(["sk"],{type:"region"}).of(value)||value}catch{return value}
  }
  function date(value){const parsed=new Date(value);return Number.isNaN(parsed.getTime())?null:parsed;}
  function dateLabel(value){const parsed=date(value);return parsed?new Intl.DateTimeFormat("sk-SK",{month:"short",year:"numeric"}).format(parsed):"";}
  function relativeTime(value){
    const parsed=date(value);if(!parsed)return "";
    const days=Math.max(0,Math.floor((Date.now()-parsed.getTime())/86400000));
    if(days===0)return "dnes";if(days===1)return "pred 1 dňom";if(days<7)return `pred ${days} dňami`;
    const weeks=Math.floor(days/7);return weeks===1?"pred 1 týždňom":`pred ${weeks} týždňami`;
  }
  function setState(message,error=false){if(!state)return;state.hidden=false;state.textContent=message;state.style.color=error?"#ff7b84":"#aeb4b6";}
  function hideState(){if(state)state.hidden=true;}
  function node(tag,className,content){const item=document.createElement(tag);if(className)item.className=className;if(content!==undefined)item.textContent=content;return item;}
  function isPlanGateError(error){return String(error?.message||"").toLowerCase().includes("pro+ plan required");}
  function normalizedPlan(value){const plan=String(value||"free").trim().toLowerCase();return plan==="pro_plus"?"pro_plus":plan==="pro"?"pro":"free";}
  function planHome(plan){return ({free:"/profil-free/",pro:"/profil-pro/",pro_plus:"/profil-pro-plus/"})[normalizedPlan(plan)];}
  function expectedPlan(){const fallback=query.get("profileRoute");if(["free","pro","pro_plus"].includes(fallback))return fallback;const path=location.pathname.replace(/\/+$/,"")+"/";if(path.startsWith("/profil-free/"))return"free";if(path.startsWith("/profil-pro/"))return"pro";if(path.startsWith("/profil-pro-plus/"))return"pro_plus";return"";}
  function applyPlan(plan,publicView=false){
    currentPlan=normalizedPlan(plan);
    document.body.classList.remove("plan-free","plan-pro","plan-pro-plus");
    document.body.classList.add(`plan-${currentPlan.replace("_","-")}`);
    const labels={free:"FREE",pro:"PRO",pro_plus:"PRO+"},badge=$("profilePlanBadge");
    if(badge){badge.textContent=labels[currentPlan];badge.className=`pro-badge profile-plan-badge-${currentPlan.replace("_","-")}`;}
    const home=planHome(currentPlan);
    document.querySelectorAll('[data-profile-home]').forEach(item=>item.dataset.route=home);
    const profileLink=document.querySelector('.nav a.active[href*="profil"]');if(profileLink)profileLink.href=home;
    if(!publicView){
      document.querySelectorAll("[data-create-feature]").forEach(link=>{
        if(currentPlan==="pro_plus"){link.removeAttribute("aria-disabled");link.onclick=null;return;}
        link.setAttribute("aria-disabled","true");
        link.onclick=event=>{event.preventDefault();location.href="/upgrade/?required=pro_plus";};
      });
      document.title=`${labels[currentPlan]} profil · Connect Sports Pro`;
    }
  }
  function weekCount(value){return `${value} ${value===1?"týždeň":value>=2&&value<=4?"týždne":"týždňov"}`;}
  function rarityLabel(value){return ({bronze:"bronzový",silver:"strieborný",gold:"zlatý",platinum:"platinový"})[String(value||"").toLowerCase()]||"CSP";}
  function badgeLabel(value){return ({"FIRST STEP":"PRVÝ KROK","ACTIVE DAYS":"AKTÍVNE DNI","ACTIVITIES":"AKTIVITY","MINUTES":"MINÚTY","TRAININGS":"TRÉNINGY","MATCHES":"ZÁPASY","WINS":"VÝHRY","ACTIVE TIME":"AKTÍVNY ČAS","STREAK":"SÉRIA","ACTIVE WEEKS":"AKTÍVNE TÝŽDNE"})[String(value||"").toUpperCase()]||String(value||"VÝZVA");}

  function getIhsCurrent(payload){return payload?.ihs?.current&&typeof payload.ihs.current==="object"?payload.ihs.current:{};}

  function weekStart(value){
    const current=new Date(value);current.setHours(0,0,0,0);
    current.setDate(current.getDate()-((current.getDay()+6)%7));
    return current;
  }

  function weeklyStreak(payload){
    const dates=[];
    (payload.recent_trainings||[]).forEach(item=>{const value=item.occurred_at||item.completed_at||item.created_at;if(date(value))dates.push(value)});
    (payload.recent_matches||[]).forEach(item=>{const value=item.occurred_at||item.completed_at||item.created_at;if(date(value))dates.push(value)});
    const active=new Set(dates.map(value=>weekStart(value).toISOString().slice(0,10)));
    let cursor=weekStart(new Date()),count=0;
    if(!active.has(cursor.toISOString().slice(0,10))){cursor.setDate(cursor.getDate()-7)}
    while(active.has(cursor.toISOString().slice(0,10))){count+=1;cursor.setDate(cursor.getDate()-7)}
    return count;
  }

  function renderProfile(payload){
    const profile=payload.profile||{},summary=payload.summary||{},disciplines=Array.isArray(payload.disciplines)?payload.disciplines:[];
    const primary=disciplines.find(item=>item.is_primary)||disciplines[0]||{};
    const name=profile.full_name||"Hráč",short=initials(name),ihs=getIhsCurrent(payload);
    const wins=Number(summary.wins)||0,losses=Number(summary.losses)||0,matches=Number(summary.matches_completed)||wins+losses;
    const rating=Number(ihs.rating),publicGrade=String(ihs.public_grade||ihs.grade||"").trim();
    const ratingText=publicGrade||(Number.isFinite(rating)?rating.toFixed(2):"—");
    const isDarts=String(primary.sport||"").toLowerCase().includes("dart")||String(primary.discipline||"").toLowerCase().includes("dart");
    const ratingLabel=publicGrade?"IHS kategória":isDarts?"Priemer":"IHS hodnotenie";
    applyPlan(profile.plan||currentPlan,isPublicView);
    ensureAccountMenu();

    text("profileName",name);text("accountName",name);text("profileInitials",short);text("accountAvatar",short);
    const flag=countryFlag(profile.country_code),place=[profile.city,countryName(profile.country_code)].filter(Boolean).join(", ");
    text("profileLocationLine",[flag,place||"Mesto a štát nie sú nastavené"].filter(Boolean).join(" "));
    text("memberSince",profile.created_at?`Člen od ${dateLabel(profile.created_at)}`:"Člen CSP");
    text("profileQuote",profile.bio?`„${profile.bio}“`:"„Lepší šport. Lepšie ja.“");
    text("profileLocation",[primary.sport,primary.discipline].filter(Boolean).join(" · ")||"Connect Sports Pro");
    text("achievementSport",primary.sport?`Progres · ${primary.sport}`:"Globálny progres");
    text("statMatches",matches);text("matchesPlayed",matches);text("statWinRate",`${Math.round(Number(summary.win_rate)||0)}%`);
    text("statRating",ratingText);text("statRatingLabel",ratingLabel);text("ratingCardLabel",ratingLabel);text("ratingCardValue",ratingText);
    text("ratingCardDelta",ihs.level?String(ihs.level).replaceAll("_"," ").toUpperCase():"Výkon CSP");
    text("matchesRecord",`${wins} výhier · ${losses} prehier`);
    const streak=weeklyStreak(payload);text("weeklyStreak",weekCount(streak));

    const avatar=String(profile.avatar_url||"").trim();
    if(avatar){const image=$("profileAvatar"),portrait=$("profilePortrait");image.src=avatar;image.alt=`Profilová fotografia: ${name}`;image.hidden=false;portrait.classList.add("has-image")}
  }

  function collectActivities(payload){
    const activities=[];
    (payload.achievements?.items||[]).filter(item=>item.unlocked&&item.unlocked_at).forEach(item=>activities.push({type:"achievement",at:item.unlocked_at,title:"Odomknutý odznak",detail:item.name||"Odznak CSP"}));
    (payload.recent_trainings||[]).forEach(item=>activities.push({type:"training",at:item.occurred_at||item.completed_at||item.created_at,title:"Dokončený tréning",detail:[item.sport,item.discipline].filter(Boolean).join(" · ")||"Športový tréning"}));
    (payload.recent_matches||[]).forEach(item=>activities.push({type:"match",at:item.occurred_at||item.completed_at||item.created_at,title:"Odohraný zápas",detail:[item.result==="win"?"Výhra":item.result==="loss"?"Prehra":"Výsledok",item.my_score!=null&&item.opponent_score!=null?`${item.my_score} : ${item.opponent_score}`:"",item.opponent_name?`proti ${item.opponent_name}`:""].filter(Boolean).join(" ")}));
    return activities.filter(item=>date(item.at)).sort((a,b)=>date(b.at)-date(a.at)).slice(0,4);
  }

  function renderActivities(payload){
    const root=$("activityList");if(!root)return;root.replaceChildren();
    const icons={achievement:"🏆",training:"▥",match:"♟♟"};
    const items=collectActivities(payload);
    if(!items.length){root.append(node("div","empty-row","Zatiaľ bez zaznamenanej aktivity."));return}
    items.forEach(item=>{const row=node("div","activity-row"),icon=node("span",`activity-symbol${item.type==="achievement"?" gold":""}`,icons[item.type]||"◎"),copy=node("div"),title=node("b","",item.title),detail=node("p","",item.detail),time=node("time","",relativeTime(item.at));copy.append(title,detail);row.append(icon,copy,time);root.append(row)});
  }

  function badgeSymbol(item){return ({first_step:"01",first_match:"▶",first_win:"V",first_tournament:"T",first_training:"TR",matches_10:"10",matches_25:"25",matches_50:"50",matches_100:"100",wins_5:"5V",wins_10:"10V",wins_50:"50V",wins_100:"100V",win_streak_3:"3×",win_streak_5:"5×",win_streak_10:"10×",group_winner:"G1",top_8:"TOP8",semifinal:"SF",finalist:"F",champion:"1",clean_tournament:"0L",champion_2:"2×",champion_5:"5×",tournaments_10:"10T"})[String(item.code||"")]||"CSP"}

  function achievementBadge(item,unlocked){
    const root=node("span","overview-achievement-badge");
    root.setAttribute("aria-label",`${rarityLabel(item.rarity)} ${unlocked?"získaný":"zamknutý"} odznak`);
    root.append(node("span","overview-achievement-ring"),node("span","overview-achievement-top","CSP"),node("span","overview-achievement-symbol",badgeSymbol(item)),node("span","overview-achievement-meta",unlocked?"ODOMKNUTÉ":"ZAMKNUTÉ"));
    return root;
  }

  function achievementCard(item){
    const unlocked=Boolean(item.unlocked),rarity=String(item.rarity||"bronze").toLowerCase();
    const card=node("article",`badge-card ${rarity} ${["gold","platinum"].includes(rarity)?"highlight":""} ${unlocked?"unlocked":"locked"}`.trim());
    const line=node("div","badge-line"),icon=achievementBadge(item,unlocked),copy=node("div"),title=node("b","",item.name||"Odznak"),points=node("span","pts",`${Number(item.points)||0} bodov`);
    copy.append(title,points);line.append(icon,copy);card.append(line);
    if(unlocked){card.append(node("span","badge-state","Odomknuté"))}
    else{const wrap=node("div","badge-progress"),bar=node("span","bar"),fill=node("i"),current=Math.max(0,Number(item.current_value)||0),target=Math.max(1,Number(item.target_value)||1);fill.style.width=`${Math.min(100,Math.round(current*100/target))}%`;bar.append(fill);wrap.append(bar,node("span","",`${Math.min(current,target)} / ${target}`));card.append(wrap)}
    return card;
  }

  function renderAchievements(payload){
    const achievements=payload.achievements||{},summary=achievements.summary||{},items=Array.isArray(achievements.items)?achievements.items:[];
    const unlocked=Number(summary.unlocked)||0,total=Number(summary.total)||items.length,percent=total?Math.round(unlocked*100/total):0;
    text("achievementPoints",new Intl.NumberFormat("sk-SK").format(Number(summary.points)||0));text("achievementCount",`${unlocked} / ${total}`);text("achievementPercent",`${percent}%`);$("achievementProgress").style.width=`${percent}%`;
    const badgeRoot=$("achievementBadges");badgeRoot.replaceChildren();
    const showcase=[...items].sort((a,b)=>Number(b.unlocked)-Number(a.unlocked)||Number(b.points)-Number(a.points)).slice(0,6);
    if(showcase.length)showcase.forEach(item=>badgeRoot.append(achievementCard(item)));else badgeRoot.append(node("div","empty-row","Zatiaľ žiadne odznaky."));
  }

  function challengeCard(item){
    const current=Math.max(0,Number(item.progress_value)||0),target=Math.max(1,Number(item.target_value)||1);
    const percent=Math.min(100,Math.round(current*100/target));
    const card=node(isPublicView?"article":"a",`challenge-overview-card ${item.medal||"silver"}`);if(!isPublicView)card.href=`/profil-pro-plus/vyzvy/?challenge=${encodeURIComponent(item.code||"")}`;
    const symbol=node("span","overview-challenge-badge");
    ["overview-challenge-shell","overview-challenge-inner","overview-challenge-green","overview-challenge-field"].forEach(name=>symbol.append(node("i",name)));
    symbol.append(node("i","overview-challenge-csp","CSP"),node("i","overview-challenge-symbol",item.badge_symbol||"CSP"),node("i","overview-challenge-year",badgeLabel(item.badge_label)));
    const copy=node("span","challenge-copy"),title=node("b","",item.title||"Výzva"),status=node("small","",item.state==="completed"?"Splnená":item.state==="joined"?`${current} / ${target} ${item.unit_label||""}`:"Pridať sa k výzve");
    const bar=node("span","challenge-bar"),fill=node("i");fill.style.width=`${percent}%`;bar.append(fill);copy.append(title,status,bar);card.append(symbol,copy);return card;
  }

  function renderChallenges(data){
    const safe=data||{},summary=safe.summary||{},root=$("challengeOverview");if(!root)return;
    const total=Number(summary.total)||0,completed=Number(summary.completed)||0,active=Number(summary.active)||0;
    text("challengeOverviewCount",`${completed} / ${total}`);text("challengeOverviewActive",`${active} aktívne`);
    root.replaceChildren();
    const items=Array.isArray(safe.items)?safe.items:[];
    const selected=[...items].sort((a,b)=>{
      const rank={joined:0,available:1,completed:2,upcoming:3,closed:4};
      return (rank[a.state]??9)-(rank[b.state]??9)||(Number(b.progress_percent)||0)-(Number(a.progress_percent)||0);
    }).slice(0,3);
    if(selected.length)selected.forEach(item=>root.append(challengeCard(item)));
    else root.append(node("div","empty-row","Výzvy zatiaľ nie sú dostupné."));
  }

  function renderGear(gear){
    const safe=gear||{};text("gearBoard",safe.board_name||"Nie je nastavené");text("gearEquipment",safe.equipment_name||"Nie je nastavené");
    const motto=safe.motto||"Vybavenie zatiaľ nie je nastavené.";text("gearMotto",`“${motto}”`);
  }

  function ensureAccountMenu(){
    const account=document.querySelector(".account");if(!account||isPublicView)return;
    account.setAttribute("role","button");account.setAttribute("tabindex","0");account.setAttribute("aria-haspopup","menu");account.setAttribute("aria-expanded","false");
    account.style.position="relative";account.style.cursor="pointer";
    if(document.getElementById("accountMenu"))return;
    const style=document.createElement("style");style.textContent=`
      .account-menu{position:absolute;right:0;top:52px;z-index:120;min-width:220px;padding:7px;border:1px solid #30383a;border-radius:10px;background:#0d1112;box-shadow:0 18px 45px rgba(0,0,0,.45);display:none}
      .account-menu.open{display:block}
      .account-menu button,.account-menu a{width:100%;min-height:40px;display:flex;align-items:center;padding:0 12px;border:0;border-radius:7px;background:transparent;color:#e8ebec;font:600 11px Inter,Arial,sans-serif;text-align:left;cursor:pointer}
      .account-menu button:hover,.account-menu a:hover{background:#171d1f}
      .account-menu .danger{color:#ff7b84;border-top:1px solid #252b2d;margin-top:5px;padding-top:5px;border-radius:0 0 7px 7px}
    `;document.head.append(style);
    const menu=document.createElement("div");menu.id="accountMenu";menu.className="account-menu";menu.setAttribute("role","menu");
    menu.innerHTML='<a id="accountProfileLink" role="menuitem">Môj profil</a><button id="accountSettings" type="button" role="menuitem">Nastavenia profilu</button><button id="accountLogout" class="danger" type="button" role="menuitem">Odhlásiť sa</button>';
    account.append(menu);
    const close=()=>{menu.classList.remove("open");account.setAttribute("aria-expanded","false")};
    const toggle=event=>{event.stopPropagation();const open=!menu.classList.contains("open");menu.classList.toggle("open",open);account.setAttribute("aria-expanded",String(open))};
    account.addEventListener("click",event=>{if(event.target.closest("#accountMenu"))return;toggle(event)});
    account.addEventListener("keydown",event=>{if(event.key==="Enter"||event.key===" "){event.preventDefault();toggle(event)}if(event.key==="Escape")close()});
    document.addEventListener("click",event=>{if(!account.contains(event.target))close()});
    document.addEventListener("keydown",event=>{if(event.key==="Escape")close()});
    document.getElementById("accountProfileLink").href=planHome(currentPlan);
    document.getElementById("accountSettings").addEventListener("click",()=>{location.href=currentPlan==="pro_plus"?"/profil-pro-plus/upravit/":"/profil/moj-profil/"});
    document.getElementById("accountLogout").addEventListener("click",async()=>{try{await window.cspAuth?.client?.auth?.signOut()}finally{location.replace("/")}}); 
  }

  function bindInteractions(){
    const sidebar=$("sidebar"),menu=$("menuToggle");if(sidebar&&menu)menu.addEventListener("click",()=>sidebar.classList.toggle("open"));
    document.querySelectorAll(".profile-tabs [data-route]").forEach(button=>button.addEventListener("click",()=>{location.href=button.dataset.route}));
    $("editProfile")?.addEventListener("click",()=>{location.href=currentPlan==="pro_plus"?"/profil-pro-plus/upravit/":"/profil/moj-profil/"});
    $("globalSearch")?.addEventListener("submit",event=>{event.preventDefault();const query=$("globalSearchInput")?.value.trim();if(query)location.href=`/search/?q=${encodeURIComponent(query)}`});
  }

  async function init(){
    bindInteractions();
    try{
      const client=window.cspAuth?.client;if(!client)throw new Error("Prihlásenie CSP nie je dostupné.");
      if(isPublicView){
        document.body.classList.add("public-mode");
        const [profileResult,ihsResult]=await Promise.all([
          client.rpc("get_public_pro_plus_profile",{p_player_id:publicPlayerId}),
          client.rpc("get_public_ihs_grade",{p_player_id:publicPlayerId,p_sport:null})
        ]);
        if(profileResult.error)throw profileResult.error;
        dashboard=profileResult.data||{};
        if(!dashboard.profile)throw new Error("Verejný profil hráča sa nenašiel.");
        dashboard.ihs={current:{public_grade:ihsResult.error?null:ihsResult.data?.grade||null}};
        renderProfile(dashboard);renderActivities(dashboard);renderAchievements(dashboard);renderGear(dashboard.gear);renderChallenges(dashboard.challenges||{});
        document.title=`${dashboard.profile.full_name||"Hráč"} – Connect Sports Pro`;
        hideState();return;
      }
      const {data:userData,error:userError}=await client.auth.getUser();
      if(userError||!userData.user){location.replace("/login/?returnTo="+encodeURIComponent(location.pathname));return}
      const {data:privateProfile,error:privateProfileError}=await window.cspAuth.getCurrentProfile(userData.user);
      if(privateProfileError)throw privateProfileError;
      const role=String(privateProfile?.role||"player").toLowerCase();
      if(privateProfile?.is_admin===true||["admin","club","organization"].includes(role)||String(privateProfile?.plan||"").toLowerCase()==="ultra"){
        location.replace("/profil-ul/");return;
      }
      currentPlan=normalizedPlan(privateProfile?.plan);
      const requiredPath=planHome(currentPlan),routePlan=expectedPlan();
      if(routePlan&&routePlan!==currentPlan){location.replace(requiredPath);return}
      applyPlan(currentPlan);

      let challengesResult={data:{},error:null};
      if(currentPlan==="pro_plus"){
        const results=await Promise.all([client.rpc("get_my_pro_plus_dashboard"),client.rpc("get_my_challenges")]);
        const dashboardResult=results[0];challengesResult=results[1];
        if(dashboardResult.error){
          if(isPlanGateError(dashboardResult.error)){location.replace("/upgrade/?required=pro_plus");return}
          throw dashboardResult.error;
        }
        dashboard=dashboardResult.data||{};
      }else{
        const challengeRequest=currentPlan==="pro"?client.rpc("get_my_challenges"):Promise.resolve({data:{},error:null});
        const [dashboardResult,achievementsResult,ihsResult,locationResult,planChallengesResult]=await Promise.all([
          client.rpc("get_my_player_profile_dashboard"),
          client.rpc("get_my_achievements"),
          client.rpc("get_my_ihs_overview"),
          client.from("profiles").select("city,country_code").eq("id",userData.user.id).maybeSingle(),
          challengeRequest
        ]);
        challengesResult=planChallengesResult||{data:{},error:null};
        if(dashboardResult.error)throw dashboardResult.error;
        if(achievementsResult.error)console.warn("[player-profile] achievements",achievementsResult.error);
        if(ihsResult.error)console.warn("[player-profile] ihs",ihsResult.error);
        if(locationResult.error)console.warn("[player-profile] location",locationResult.error);
        dashboard=dashboardResult.data||{};
        dashboard.profile={...(dashboard.profile||{}),...(privateProfile||{}),...(locationResult.data||{}),plan:currentPlan};
        dashboard.achievements=achievementsResult.data||{};
        dashboard.ihs=ihsResult.data||{};
        dashboard.gear={};
      }
      dashboard.profile={...(dashboard.profile||{}),plan:currentPlan};
      renderProfile(dashboard);renderActivities(dashboard);renderAchievements(dashboard);renderGear(dashboard.gear);
      if(currentPlan==="free")renderChallenges({});
      else if(challengesResult.error)console.warn("[player-profile] challenges",challengesResult.error);
      else renderChallenges(challengesResult.data||{});
      hideState();
    }catch(error){console.error("[player-profile]",error);setState(error.message||"Hráčsky profil sa nepodarilo načítať.",true)}
  }

  window.addEventListener("DOMContentLoaded",init);
})();
