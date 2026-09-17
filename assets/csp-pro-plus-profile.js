"use strict";

(function(){
  const $=id=>document.getElementById(id);
  const state=$("pageState");
  const query=new URLSearchParams(location.search);
  const publicPlayerId=query.get("id");
  const isPublicView=query.get("view")==="public"&&Boolean(publicPlayerId);
  let dashboard=null;

  function text(id,value){const node=$(id);if(node)node.textContent=value??"";}
  function initials(name){return String(name||"Player").trim().split(/\s+/).slice(0,2).map(part=>part[0]||"").join("").toUpperCase();}
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
  function dateLabel(value){const parsed=date(value);return parsed?new Intl.DateTimeFormat("en-GB",{month:"short",year:"numeric"}).format(parsed):"";}
  function relativeTime(value){
    const parsed=date(value);if(!parsed)return "";
    const days=Math.max(0,Math.floor((Date.now()-parsed.getTime())/86400000));
    if(days===0)return "today";if(days===1)return "1 day ago";if(days<7)return `${days} days ago`;
    const weeks=Math.floor(days/7);return weeks===1?"1 week ago":`${weeks} weeks ago`;
  }
  function setState(message,error=false){if(!state)return;state.hidden=false;state.textContent=message;state.style.color=error?"#ff7b84":"#aeb4b6";}
  function hideState(){if(state)state.hidden=true;}
  function node(tag,className,content){const item=document.createElement(tag);if(className)item.className=className;if(content!==undefined)item.textContent=content;return item;}
  function isPlanGateError(error){return String(error?.message||"").toLowerCase().includes("pro+ plan required");}

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
    const name=profile.full_name||"Player",short=initials(name),ihs=getIhsCurrent(payload);
    const wins=Number(summary.wins)||0,losses=Number(summary.losses)||0,matches=Number(summary.matches_completed)||wins+losses;
    const rating=Number(ihs.rating),publicGrade=String(ihs.public_grade||ihs.grade||"").trim();
    const ratingText=publicGrade||(Number.isFinite(rating)?rating.toFixed(2):"—");
    const isDarts=String(primary.sport||"").toLowerCase().includes("dart")||String(primary.discipline||"").toLowerCase().includes("dart");
    const ratingLabel=publicGrade?"IHS Grade":isDarts?"Average":"IHS Rating";

    text("profileName",name);text("accountName",name);text("profileInitials",short);text("accountAvatar",short);
    const flag=countryFlag(profile.country_code),place=[profile.city,countryName(profile.country_code)].filter(Boolean).join(", ");
    text("profileLocationLine",[flag,place||"Mesto a štát nie sú nastavené"].filter(Boolean).join(" "));
    text("memberSince",profile.created_at?`Member since ${dateLabel(profile.created_at)}`:"CSP member");
    text("profileQuote",profile.bio?`“${profile.bio}”`:"“Better sport. A better me.”");
    text("profileLocation",[primary.sport,primary.discipline].filter(Boolean).join(" · ")||"Connect Sports Pro");
    text("achievementSport",primary.sport?`${primary.sport} progression`:"Global progression");
    text("statMatches",matches);text("matchesPlayed",matches);text("statWinRate",`${Math.round(Number(summary.win_rate)||0)}%`);
    text("statRating",ratingText);text("statRatingLabel",ratingLabel);text("ratingCardLabel",ratingLabel);text("ratingCardValue",ratingText);
    text("ratingCardDelta",ihs.level?String(ihs.level).replaceAll("_"," ").toUpperCase():"CSP performance");
    text("matchesRecord",`${wins} wins · ${losses} losses`);
    const streak=weeklyStreak(payload);text("weeklyStreak",`${streak} ${streak===1?"week":"weeks"}`);

    const avatar=String(profile.avatar_url||"").trim();
    if(avatar){const image=$("profileAvatar"),portrait=$("profilePortrait");image.src=avatar;image.alt=`Profile photo: ${name}`;image.hidden=false;portrait.classList.add("has-image")}
  }

  function collectActivities(payload){
    const activities=[];
    (payload.achievements?.items||[]).filter(item=>item.unlocked&&item.unlocked_at).forEach(item=>activities.push({type:"achievement",at:item.unlocked_at,title:"Achievement unlocked",detail:item.name||"CSP achievement"}));
    (payload.recent_trainings||[]).forEach(item=>activities.push({type:"training",at:item.occurred_at||item.completed_at||item.created_at,title:"Completed training session",detail:[item.sport,item.discipline].filter(Boolean).join(" · ")||"Sports training"}));
    (payload.recent_matches||[]).forEach(item=>activities.push({type:"match",at:item.occurred_at||item.completed_at||item.created_at,title:"Played a match",detail:[item.result==="win"?"Won":item.result==="loss"?"Lost":"Result",item.my_score!=null&&item.opponent_score!=null?`${item.my_score} - ${item.opponent_score}`:"",item.opponent_name?`vs. ${item.opponent_name}`:""].filter(Boolean).join(" ")}));
    return activities.filter(item=>date(item.at)).sort((a,b)=>date(b.at)-date(a.at)).slice(0,4);
  }

  function renderActivities(payload){
    const root=$("activityList");if(!root)return;root.replaceChildren();
    const icons={achievement:"🏆",training:"▥",match:"♟♟"};
    const items=collectActivities(payload);
    if(!items.length){root.append(node("div","empty-row","No recorded activity yet."));return}
    items.forEach(item=>{const row=node("div","activity-row"),icon=node("span",`activity-symbol${item.type==="achievement"?" gold":""}`,icons[item.type]||"◎"),copy=node("div"),title=node("b","",item.title),detail=node("p","",item.detail),time=node("time","",relativeTime(item.at));copy.append(title,detail);row.append(icon,copy,time);root.append(row)});
  }

  function badgeSymbol(item){const code=String(item.code||"");const numeric=code.match(/\d+/);return numeric?numeric[0]:String(item.name||"CSP").split(/\s+/).map(x=>x[0]).join("").slice(0,3).toUpperCase()}

  function achievementCard(item){
    const unlocked=Boolean(item.unlocked),rarity=String(item.rarity||"bronze").toLowerCase();
    const card=node("article",`badge-card ${["gold","platinum"].includes(rarity)?"highlight":""} ${unlocked?"":"locked"}`.trim());
    const line=node("div","badge-line"),icon=node("span",`badge-icon ${rarity==="silver"?"silver":""}`,badgeSymbol(item)),copy=node("div"),title=node("b","",item.name||"Achievement"),points=node("span","pts",`${Number(item.points)||0} pts`);
    copy.append(title,points);line.append(icon,copy);card.append(line);
    if(unlocked){card.append(node("span","badge-state","Unlocked"))}
    else{const wrap=node("div","badge-progress"),bar=node("span","bar"),fill=node("i"),current=Math.max(0,Number(item.current_value)||0),target=Math.max(1,Number(item.target_value)||1);fill.style.width=`${Math.min(100,Math.round(current*100/target))}%`;bar.append(fill);wrap.append(bar,node("span","",`${Math.min(current,target)} / ${target}`));card.append(wrap)}
    return card;
  }

  function renderAchievements(payload){
    const achievements=payload.achievements||{},summary=achievements.summary||{},items=Array.isArray(achievements.items)?achievements.items:[];
    const unlocked=Number(summary.unlocked)||0,total=Number(summary.total)||items.length,percent=total?Math.round(unlocked*100/total):0;
    text("achievementPoints",new Intl.NumberFormat("en-US").format(Number(summary.points)||0));text("achievementCount",`${unlocked} / ${total}`);text("achievementPercent",`${percent}%`);$("achievementProgress").style.width=`${percent}%`;
    const badgeRoot=$("achievementBadges");badgeRoot.replaceChildren();
    const showcase=[...items].sort((a,b)=>Number(b.unlocked)-Number(a.unlocked)||Number(b.points)-Number(a.points)).slice(0,6);
    if(showcase.length)showcase.forEach(item=>badgeRoot.append(achievementCard(item)));else badgeRoot.append(node("div","empty-row","No achievements yet."));
  }

  function challengeCard(item){
    const current=Math.max(0,Number(item.progress_value)||0),target=Math.max(1,Number(item.target_value)||1);
    const percent=Math.min(100,Math.round(current*100/target));
    const card=node(isPublicView?"article":"a",`challenge-overview-card ${item.medal||"silver"}`);if(!isPublicView)card.href=`/profil-pro-plus/vyzvy/?challenge=${encodeURIComponent(item.code||"")}`;
    const symbol=node("span","challenge-symbol",item.badge_symbol||"CSP"),copy=node("span","challenge-copy"),title=node("b","",item.title||"Výzva"),status=node("small","",item.state==="completed"?"Splnená":item.state==="joined"?`${current} / ${target} ${item.unit_label||""}`:"Pridať sa k výzve");
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

  function bindInteractions(){
    const sidebar=$("sidebar"),menu=$("menuToggle");if(sidebar&&menu)menu.addEventListener("click",()=>sidebar.classList.toggle("open"));
    document.querySelectorAll(".profile-tabs [data-route]").forEach(button=>button.addEventListener("click",()=>{location.href=button.dataset.route}));
    $("editProfile")?.addEventListener("click",()=>{location.href="/profil-pro-plus/upravit/"});
    $("globalSearch")?.addEventListener("submit",event=>{event.preventDefault();const query=$("globalSearchInput")?.value.trim();if(query)location.href=`/search/?q=${encodeURIComponent(query)}`});
  }

  async function init(){
    bindInteractions();
    try{
      const client=window.cspAuth?.client;if(!client)throw new Error("CSP authentication is unavailable.");
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
      const [dashboardResult,challengesResult]=await Promise.all([client.rpc("get_my_pro_plus_dashboard"),client.rpc("get_my_challenges")]);
      if(dashboardResult.error){
        if(isPlanGateError(dashboardResult.error)){location.replace("/upgrade/?required=pro_plus");return}
        throw dashboardResult.error;
      }
      dashboard=dashboardResult.data||{};renderProfile(dashboard);renderActivities(dashboard);renderAchievements(dashboard);renderGear(dashboard.gear);
      if(challengesResult.error)console.warn("[pro-plus-profile] challenges",challengesResult.error);else renderChallenges(challengesResult.data||{});
      hideState();
    }catch(error){console.error("[pro-plus-profile]",error);setState(error.message||"PRO+ profile could not be loaded.",true)}
  }

  window.addEventListener("DOMContentLoaded",init);
})();
