"use strict";

const ACHIEVEMENTS_SUPABASE_URL="https://lcmoykaqvvfybtobhtqg.supabase.co";
const ACHIEVEMENTS_SUPABASE_KEY="sb_publishable_h3_yK3K_GUahLdz13dDWDg_PzxGE6xR";

const achievementEsc=value=>String(value??"").replace(/[&<>'"]/g,char=>({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"}[char]));
const achievementPlan=value=>String(value||"free").toLowerCase()==="pro_plus"?"PRO+":String(value||"free").toUpperCase();
const achievementProfileHome=value=>({free:"/FREE/",pro:"/PRO/",pro_plus:"/PRO+/"})[String(value||"free").toLowerCase()]||"/FREE/";
const achievementInitials=name=>String(name||"Hráč").trim().split(/\s+/).slice(0,2).map(x=>x[0]).join("").toUpperCase();
const achievementDate=value=>{const d=new Date(value);return Number.isNaN(d.getTime())?"":new Intl.DateTimeFormat("sk-SK",{day:"numeric",month:"short",year:"numeric"}).format(d)};
const achievementBadgeLabel=code=>({first_step:"01",first_match:"▶",first_win:"V",first_tournament:"T",first_training:"TR",matches_10:"10",matches_25:"25",matches_50:"50",matches_100:"100",wins_5:"5V",wins_10:"10V",wins_50:"50V",wins_100:"100V",win_streak_3:"3×",win_streak_5:"5×",win_streak_10:"10×",group_winner:"G1",top_8:"TOP8",semifinal:"SF",finalist:"F",champion:"1",clean_tournament:"0L",champion_2:"2×",champion_5:"5×",tournaments_10:"10T"}[code]||"CSP");
const categoryLabel=value=>({zaciatky:"Začiatky",progres:"Progres",konzistencia:"Konzistencia",vykon:"Výkon",vynimocne:"Výnimočné"}[value]||value||"Achievement");
const achievementRarityLabel=value=>({bronze:"BRONZE",silver:"SILVER",gold:"GOLD",platinum:"PLATINUM"}[String(value||"").toLowerCase()]||"CSP");

function setAchievementProfile(profile){
  const plan=String(profile.plan||"free").toLowerCase()==="pro_plus"?"pro_plus":String(profile.plan||"free").toLowerCase()==="pro"?"pro":"free";
  const home=achievementProfileHome(plan);
  document.querySelector(".shell")?.classList.add(`plan-${plan.replace("_","-")}`);
  document.querySelectorAll("[data-player-home]").forEach(link=>link.href=home);
  const sectionRoutes={
    "/profil/turnaje/":home+"turnaje/",
    "/profil/treningy/":home+"treningy/",
    "/profil/rebricky/":home+"rebricky/",
    "/profil/priatelia/":home+"priatelia/",
    "/profil/achievements/":home+"achievements/",
    "/profil/moj-profil/":home+"moj-profil/"
  };
  document.querySelectorAll("a[href]").forEach(link=>{const next=sectionRoutes[link.getAttribute("href")];if(next)link.href=next;});
  if(plan==="pro_plus")document.querySelectorAll('a[href="/profil-pro-plus/vyzvy/"]').forEach(link=>link.href=home+"vyzvy/");
  document.querySelectorAll("[data-create-feature]").forEach(link=>{
    if(plan==="pro_plus"){link.removeAttribute("aria-disabled");return}
    link.setAttribute("aria-disabled","true");
    link.addEventListener("click",event=>{event.preventDefault();location.href="/upgrade/?required=pro_plus";});
  });
  document.querySelectorAll("[data-achievement-player-name]").forEach(el=>el.textContent=profile.full_name||"Hráč");
  document.querySelectorAll("[data-achievement-plan]").forEach(el=>el.textContent=`${achievementPlan(plan)} účet`);
  document.querySelectorAll("[data-achievement-avatar]").forEach(el=>{
    const avatar=String(profile.avatar_url||"").trim();
    el.innerHTML=avatar?`<img src="${achievementEsc(avatar)}" alt="${achievementEsc(profile.full_name||"Hráč")}">`:achievementEsc(achievementInitials(profile.full_name));
  });
}
function achievementCard(item){
  const current=Math.max(0,Number(item.current_value)||0),target=Math.max(1,Number(item.target_value)||1),pct=Math.min(100,Math.round(current*100/target)),unlocked=!!item.unlocked;
  const progressText=unlocked?(item.unlocked_at?`Získané ${achievementDate(item.unlocked_at)}`:"Získané"):`${Math.min(current,target)} / ${target}`;
  const rarityLabel=achievementRarityLabel(item.rarity);
  const sealState=unlocked?"EARNED":"LOCKED";
  return `<article class="achievement-card ${achievementEsc(item.rarity)} ${unlocked?"unlocked":"locked"}" data-achievement-category="${achievementEsc(item.category)}" data-achievement-state="${unlocked?"unlocked":"locked"}">
    <div class="card-top"><span class="achievement-badge" aria-label="${achievementEsc(rarityLabel)} ${unlocked?"získaný":"zamknutý"} achievement"><span class="achievement-badge-ring"></span><span class="achievement-badge-top">CSP</span><span class="achievement-badge-symbol">${achievementEsc(achievementBadgeLabel(item.code))}</span><span class="achievement-badge-meta">${sealState}</span></span><span class="achievement-points">+${Number(item.points)||0} B</span></div>
    <p class="achievement-category">${achievementEsc(categoryLabel(item.category))}</p>
    <h3>${achievementEsc(item.name)}</h3>
    <p>${achievementEsc(item.description)}</p>
    <div class="achievement-progress"><div class="line"><i style="width:${unlocked?100:pct}%"></i></div><div class="progress-copy"><span>${unlocked?"ODOMKNUTÉ":"PROGRES"}</span><b>${achievementEsc(progressText)}</b></div></div>
    <span class="achievement-status">${unlocked?"✓":"•"}</span>
  </article>`;
}

function renderAchievements(payload){
  const summary=payload?.summary||{},items=Array.isArray(payload?.items)?payload.items:[];
  const root=document.getElementById("achievement-content");
  if(!root)return;
  root.innerHTML=`<div class="achievement-shell">
    <div class="achievement-summary">
      <section class="achievement-summary-card primary"><span>Achievement body</span><strong>${Number(summary.points)||0}</strong><small>Global Core Series 01 · beta</small></section>
      <section class="achievement-summary-card green"><span>Odomknuté</span><strong>${Number(summary.unlocked)||0}</strong><small>z ${Number(summary.total)||items.length} achievementov</small></section>
      <section class="achievement-summary-card"><span>Zostáva</span><strong>${Math.max(0,(Number(summary.total)||items.length)-(Number(summary.unlocked)||0))}</strong><small>ďalších cieľov</small></section>
    </div>
    <div class="achievement-toolbar"><div class="filters"><button class="achievement-filter active" data-achievement-filter="all">Všetky</button><button class="achievement-filter" data-achievement-filter="unlocked">Získané</button><button class="achievement-filter" data-achievement-filter="locked">Rozpracované</button></div><div class="achievement-legend"><span class="bronze"><i></i>Bronze</span><span class="silver"><i></i>Silver</span><span class="gold"><i></i>Gold</span><span class="platinum"><i></i>Platinum</span></div></div>
    <div id="achievement-grid" class="achievement-grid">${items.length?items.map(achievementCard).join(""):'<div class="achievement-empty">Achievementy zatiaľ nie sú dostupné.</div>'}</div>
    <div class="achievement-note"><b>Beta verzia:</b> Global Core achievementy sa udeľujú automaticky z overených CSP dát naprieč športmi — oficiálne zápasy, ligy, dvojfázové turnaje, výsledky a tréningy.</div>
  </div>`;
  root.querySelectorAll("[data-achievement-filter]").forEach(button=>button.addEventListener("click",()=>{
    const filter=button.dataset.achievementFilter;
    root.querySelectorAll("[data-achievement-filter]").forEach(x=>x.classList.toggle("active",x===button));
    root.querySelectorAll(".achievement-card").forEach(card=>card.hidden=filter!=="all"&&card.dataset.achievementState!==filter);
  }));
}

function bindAchievementMobileMenu(){
  const sidebar=document.getElementById("profile-sidebar"),backdrop=document.querySelector("[data-profile-menu-backdrop]"),toggle=document.querySelector("[data-profile-menu-toggle]");
  if(!sidebar||!backdrop||!toggle)return;
  const setOpen=open=>{sidebar.classList.toggle("open",open);backdrop.classList.toggle("open",open);backdrop.setAttribute("aria-hidden",String(!open));toggle.setAttribute("aria-expanded",String(open));document.body.classList.toggle("profile-menu-open",open)};
  toggle.addEventListener("click",()=>setOpen(!sidebar.classList.contains("open")));
  document.querySelectorAll("[data-profile-menu-close]").forEach(x=>x.addEventListener("click",()=>setOpen(false)));
  backdrop.addEventListener("click",()=>setOpen(false));
}

async function initAchievements(){
  bindAchievementMobileMenu();
  const root=document.getElementById("achievement-content");
  try{
    if(!window.supabase)throw new Error("Supabase client unavailable");
    const client=window.supabase.createClient(ACHIEVEMENTS_SUPABASE_URL,ACHIEVEMENTS_SUPABASE_KEY,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}});
    const {data:userData,error:userError}=await client.auth.getUser();
    if(userError||!userData.user){location.href="/login/?returnTo="+encodeURIComponent(location.pathname+location.search);return}
    const [profileResult,achievementResult]=await Promise.all([
      client.from("profiles").select("id,full_name,plan,role,avatar_url").eq("id",userData.user.id).single(),
      client.rpc("get_my_achievements")
    ]);
    if(profileResult.error)throw profileResult.error;
    if(achievementResult.error)throw achievementResult.error;
    setAchievementProfile(profileResult.data||{});
    renderAchievements(achievementResult.data||{});
  }catch(error){
    console.error("[achievements]",error);
    if(root)root.innerHTML='<section class="panel panel-pad"><div class="empty">Achievementy sa nepodarilo načítať. Obnov stránku.</div></section>';
  }
}

window.addEventListener("DOMContentLoaded",initAchievements);
