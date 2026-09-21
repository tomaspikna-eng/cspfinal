"use strict";

(function(){
  const $=id=>document.getElementById(id);
  const db=window.cspAuth?.client;
  let user=null;
  let primaryDiscipline=null;

  function initials(name){return String(name||"Hráč").trim().split(/\s+/).slice(0,2).map(part=>part[0]||"").join("").toUpperCase()||"H"}
  function setState(message,error=false){const root=$("pageState");root.innerHTML="";root.textContent=message;root.style.color=error?"#ff7b84":"#969e9a";root.hidden=false;$("editor").hidden=true}
  function toast(message,error=false){const root=$("toast");root.textContent=message;root.classList.toggle("error",error);root.hidden=false;clearTimeout(toast.timer);toast.timer=setTimeout(()=>{root.hidden=true},3000)}
  function renderAvatar(profile){
    const root=$("avatarPreview");root.replaceChildren();
    if(profile.avatar_url){const image=new Image();image.src=profile.avatar_url;image.alt="Profilová fotografia";root.append(image)}
    else{const mark=document.createElement("span");mark.id="avatarInitials";mark.textContent=initials(profile.full_name);root.append(mark)}
  }
  function normalizeCountry(value){return String(value||"").trim().toUpperCase()}
  function isPlanGateError(error){return String(error?.message||"").toLowerCase().includes("pro+ plan required")}

  async function load(){
    try{
      if(!db)throw new Error("Supabase klient nie je dostupný.");
      const {data:userResult,error:userError}=await db.auth.getUser();
      if(userError||!userResult.user){location.replace("/login/?returnTo="+encodeURIComponent(location.pathname));return}
      user=userResult.user;

      const {data,error}=await db.rpc("get_my_pro_plus_dashboard");
      if(error){
        if(isPlanGateError(error)){location.replace("/upgrade/?required=pro_plus");return}
        throw error;
      }

      const payload=data||{},profile=payload.profile||{},disciplines=Array.isArray(payload.disciplines)?payload.disciplines:[];
      const {data:privateSettings,error:privateSettingsError}=await db.rpc("get_my_private_profile_settings");
      if(privateSettingsError)throw privateSettingsError;
      document.getElementById("shellName").textContent=profile.full_name||"Hráč";
      document.getElementById("shellPlan").textContent="PRO+ účet";
      const shellAvatar=document.getElementById("shellAvatar");if(shellAvatar){shellAvatar.textContent=initials(profile.full_name);}
      document.querySelectorAll("[data-create-feature]").forEach(link=>link.removeAttribute("aria-disabled"));
      primaryDiscipline=disciplines.find(item=>item.is_primary)||disciplines[0]||null;
      $("fullName").value=profile.full_name||"";$("bio").value=profile.bio||"";$("bioCount").textContent=String($("bio").value.length);
      $("birthYear").value=privateSettings?.birth_year||"";
      $("city").value=profile.city||"";$("countryCode").value=profile.country_code||"";if($("clubName"))$("clubName").value=profile.club_name||"";
      $("sport").value=primaryDiscipline?.sport||"";$("discipline").value=primaryDiscipline?.discipline||"";
      $("gearBoard").value=payload.gear?.board_name||"";$("gearEquipment").value=payload.gear?.equipment_name||"";$("gearMotto").value=payload.gear?.motto||"";
      $("profileNameHero").textContent=profile.full_name||"Hráč";renderAvatar(profile);
      $("pageState").hidden=true;$("editor").hidden=false;
    }catch(error){console.error("[pro-plus-edit] load",error);setState(error.message||"PRO+ profil sa nepodarilo načítať.",true)}
  }

  async function save(event){
    event.preventDefault();
    const button=$("saveButton");button.disabled=true;button.textContent="Ukladám…";
    try{
      const fullName=$("fullName").value.trim(),bio=$("bio").value.trim(),city=$("city").value.trim(),countryCode=normalizeCountry($("countryCode").value),clubName=$("clubName")?$("clubName").value.trim():"";
      const birthYearRaw=$("birthYear").value.trim(),birthYear=birthYearRaw?Number(birthYearRaw):null;
      const currentYear=new Date().getFullYear();
      const sport=$("sport").value.trim(),discipline=$("discipline").value.trim();
      if(!fullName)throw new Error("Meno nemôže byť prázdne.");
      if(countryCode&&!/^[A-Z]{2}$/.test(countryCode))throw new Error("Štát zadaj ako dvojpísmenový ISO kód, napríklad SK.");
      if(birthYear!==null&&(!Number.isInteger(birthYear)||birthYear<1900||birthYear>currentYear))throw new Error("Rok narodenia zadaj v rozsahu 1900 až "+currentYear+".");

      const patch={full_name:fullName,bio:bio||null,city:city||null,country_code:countryCode||null,birth_year:birthYear};
      if($("clubName"))patch.club_name=clubName||null;
      const {error:profileError}=await db.rpc("update_my_player_profile_settings",{p_patch:patch});
      if(profileError)throw profileError;

      if(primaryDiscipline?.id){
        const {error}=await db.from("player_disciplines").update({sport:sport||primaryDiscipline.sport,discipline:discipline||null}).eq("id",primaryDiscipline.id).eq("player_id",user.id);
        if(error)throw error;
      }else if(sport||discipline){
        const {data,error}=await db.from("player_disciplines").insert({player_id:user.id,sport:sport||"Šport",discipline:discipline||null,is_primary:true}).select("id,sport,discipline,is_primary").single();
        if(error)throw error;primaryDiscipline=data;
      }

      const {error:gearError}=await db.rpc("update_my_pro_plus_gear",{p_board_name:$("gearBoard").value.trim(),p_equipment_name:$("gearEquipment").value.trim(),p_motto:$("gearMotto").value.trim()});
      if(gearError)throw gearError;

      $("profileNameHero").textContent=fullName;const mark=$("avatarInitials");if(mark)mark.textContent=initials(fullName);
      toast("PRO+ profil bol uložený.");
    }catch(error){console.error("[pro-plus-edit] save",error);toast(error.message||"Profil sa nepodarilo uložiť.",true)}
    finally{button.disabled=false;button.textContent="Uložiť zmeny"}
  }

  $("bio")?.addEventListener("input",()=>{$("bioCount").textContent=String($("bio").value.length)});
  $("avatarButton")?.addEventListener("click",()=>$("avatarInput").click());
  $("profileForm")?.addEventListener("submit",save);
  window.addEventListener("DOMContentLoaded",()=>{
    const sidebar=document.getElementById("profile-sidebar"),toggle=document.querySelector("[data-profile-menu-toggle]"),close=document.querySelector("[data-profile-menu-close]"),backdrop=document.querySelector("[data-profile-menu-backdrop]");
    const setOpen=open=>{sidebar?.classList.toggle("open",open);backdrop?.classList.toggle("open",open);toggle?.setAttribute("aria-expanded",String(open));};
    toggle?.addEventListener("click",()=>setOpen(!sidebar?.classList.contains("open")));close?.addEventListener("click",()=>setOpen(false));backdrop?.addEventListener("click",()=>setOpen(false));
    load();
  });
})();
