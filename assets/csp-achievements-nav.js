(function(){
  "use strict";
  function inject(){
    const nav=document.querySelector("#profile-sidebar .nav, .sidebar .nav");
    if(!nav||nav.querySelector('[href="/profil/achievements/"]'))return;
    const anchor=document.createElement("a");
    anchor.className="nav-link"+(location.pathname.startsWith("/profil/achievements")?" active":"");
    anchor.href="/profil/achievements/";
    anchor.innerHTML='<span class="nav-icon">◆</span>Achievements';
    const friends=[...nav.querySelectorAll("a")].find(a=>a.getAttribute("href")==="/profil/priatelia/");
    if(friends)friends.insertAdjacentElement("beforebegin",anchor);else nav.appendChild(anchor);
  }
  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",()=>setTimeout(inject,0));else setTimeout(inject,0);
  new MutationObserver(inject).observe(document.documentElement,{childList:true,subtree:true});
})();
