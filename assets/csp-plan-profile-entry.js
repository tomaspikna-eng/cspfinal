"use strict";

(function(){
  const route=document.documentElement.dataset.profileRoute;
  if(!["free","pro"].includes(route))return;
  const params=new URLSearchParams(location.search);
  params.set("profileRoute",route);
  location.replace("/profil-pro-plus/?"+params.toString()+location.hash);
})();
