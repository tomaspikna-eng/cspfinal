"use strict";

(function(){
  const $=id=>document.getElementById(id);
  const state=$("pageState");
  let dashboard=null;

  function text(id,value){const node=$(id);if(node)node.textContent=value??"";}
  function initials(name){return String(name||"Player").trim().split(/\s+/).slice(0,2).map(part=>part[0]||"").join("").toUpperCase();}
  function handle(name){return "@"+String(name||"player").normalize("NFD").replace(/[\u0300-\u036f]/g,"").toLowerCase().replace(/[^a-z0-9]+/g,"").slice(0,24);}
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
    const rating=Number(ihs.rating),ratingText=Number.isFinite(rating)?rating.toFixed(2):"—";
    const isDarts=String(primary.sport||"").toLowerCase().includes("dart")||String(primary.discipline||"").toLowerCase().includes("dart");
    const ratingLabel=isDarts?"Average":"IHS Rating";

    text("profileName",name);text("accountName",name);text("profileInitials",short);text("accountAvatar",short);
    text("profileHandle",handle(name));text("memberSince",profile.created_at?`Member since ${dateLabel(profile.created_at)}`:"CSP member");
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

  function lockedCard(item){
    const card=node("article","locked-card"),symbol=node("span","locked-symbol",badgeSymbol(item));
    card.append(symbol,node("b","",item.name||"Achievement"),node("span","",`${Number(item.points)||0} pts`),node("small","","🔒  PRO+"));return card;
  }

  function renderAchievements(payload){
    const achievements=payload.achievements||{},summary=achievements.summary||{},items=Array.isArray(achievements.items)?achievements.items:[];
    const unlocked=Number(summary.unlocked)||0,total=Number(summary.total)||items.length,percent=total?Math.round(unlocked*100/total):0;
    text("achievementPoints",new Intl.NumberFormat("en-US").format(Number(summary.points)||0));text("achievementCount",`${unlocked} / ${total}`);text("achievementPercent",`${percent}%`);$("achievementProgress").style.width=`${percent}%`;
    const badgeRoot=$("achievementBadges");badgeRoot.replaceChildren();
    const showcase=[...items].sort((a,b)=>Number(b.unlocked)-Number(a.unlocked)||Number(b.points)-Number(a.points)).slice(0,6);
    if(showcase.length)showcase.forEach(item=>badgeRoot.append(achievementCard(item)));else badgeRoot.append(node("div","empty-row","No achievements yet."));
    const lockedRoot=$("lockedAchievements");lockedRoot.replaceChildren();const locked=items.filter(item=>!item.unlocked).slice(0,3);
    if(locked.length)locked.forEach(item=>lockedRoot.append(lockedCard(item)));else lockedRoot.append(node("div","empty-row","All current achievements unlocked."));
  }

  function renderGear(gear){
    const safe=gear||{};text("gearBoard",safe.board_name||"Not set");text("gearEquipment",safe.equipment_name||"Not set");
    const motto=safe.motto||"Good equipment helps, but better habits win matches.";text("gearMotto",`“${motto}”`);
  }

  async function editGear(){
    const client=window.cspAuth?.client;if(!client||!dashboard)return;
    const current=dashboard.gear||{};
    const board=window.prompt("My board",current.board_name||"");if(board===null)return;
    const equipment=window.prompt("My equipment",current.equipment_name||"");if(equipment===null)return;
    const motto=window.prompt("My gear motto",current.motto||"");if(motto===null)return;
    setState("Saving equipment…");
    const {data,error}=await client.rpc("update_my_pro_plus_gear",{p_board_name:board,p_equipment_name:equipment,p_motto:motto});
    if(error){setState(error.message||"Equipment could not be saved.",true);window.setTimeout(hideState,2600);return}
    dashboard.gear=data||{};renderGear(dashboard.gear);hideState();
  }

  function bindInteractions(){
    const sidebar=$("sidebar"),menu=$("menuToggle");if(sidebar&&menu)menu.addEventListener("click",()=>sidebar.classList.toggle("open"));
    document.querySelectorAll(".profile-tabs [data-route]").forEach(button=>button.addEventListener("click",()=>{location.href=button.dataset.route}));
    $("editProfile")?.addEventListener("click",()=>{location.href="/profil/moj-profil/"});
    $("editGear")?.addEventListener("click",editGear);$("openAchievements")?.addEventListener("click",()=>{location.href="/profil/achievements/"});
    $("globalSearch")?.addEventListener("submit",event=>{event.preventDefault();const query=$("globalSearchInput")?.value.trim();if(query)location.href=`/search/?q=${encodeURIComponent(query)}`});
  }

  async function init(){
    bindInteractions();
    try{
      const client=window.cspAuth?.client;if(!client)throw new Error("CSP authentication is unavailable.");
      const {data:userData,error:userError}=await client.auth.getUser();
      if(userError||!userData.user){location.replace("/login/?returnTo="+encodeURIComponent(location.pathname));return}
      const {data,error}=await client.rpc("get_my_pro_plus_dashboard");
      if(error){
        if(String(error.code)==="42501"||String(error.message||"").includes("PRO+")){location.replace("/upgrade/?required=pro_plus");return}
        throw error;
      }
      dashboard=data||{};renderProfile(dashboard);renderActivities(dashboard);renderAchievements(dashboard);renderGear(dashboard.gear);hideState();
    }catch(error){console.error("[pro-plus-profile]",error);setState(error.message||"PRO+ profile could not be loaded.",true)}
  }

  window.addEventListener("DOMContentLoaded",init);
})();
