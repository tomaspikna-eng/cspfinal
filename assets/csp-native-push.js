(function(global){
  'use strict';
  var C=global.Capacitor;
  if(!C||!C.isNativePlatform||!C.isNativePlatform()) return;
  var P=C.Plugins&&C.Plugins.PushNotifications;
  if(!P||!global.cspAuth) return;
  var registeredToken=null;

  async function saveToken(token){
    if(!token||token===registeredToken) return;
    var s=await global.cspAuth.getSession();
    var session=s&&s.data&&s.data.session;
    if(!session) return;
    var r=await global.cspAuth.client.rpc('register_push_device',{
      p_token:token,
      p_platform:'android',
      p_device_name:(navigator.userAgent||'Android').slice(0,180),
      p_app_version:'1.0.0'
    });
    if(r.error){ console.error('[csp-native-push] register_push_device failed',r.error); return; }
    registeredToken=token;
  }

  async function setup(){
    try{
      if(P.createChannel){
        await P.createChannel({id:'csp_match_critical',name:'CSP zápasy',description:'Kritické výzvy k zápasu, zmena stola a súper pripravený',importance:5,visibility:1,sound:'default',vibration:true});
        await P.createChannel({id:'csp_general',name:'CSP upozornenia',description:'Profil, turnaje, ligy, IHS a klubové upozornenia',importance:3,visibility:1,sound:'default',vibration:true});
      }
      var perm=await P.checkPermissions();
      if(perm.receive!=='granted') perm=await P.requestPermissions();
      if(perm.receive!=='granted') return;
      await P.addListener('registration',function(t){ saveToken(t&&t.value); });
      await P.addListener('registrationError',function(e){ console.error('[csp-native-push] registration error',e); });
      await P.addListener('pushNotificationActionPerformed',function(ev){
        var d=ev&&ev.notification&&ev.notification.data||{};
        var u=d.action_url||'/';
        if(/^https:\/\/connectsportspro\.com\//.test(u)) location.href=u;
        else if(u.charAt(0)==='/') location.href=u;
      });
      await P.register();
      global.cspAuth.client.auth.onAuthStateChange(function(event){
        if(event==='SIGNED_IN'&&registeredToken) saveToken(registeredToken);
      });
    }catch(e){ console.error('[csp-native-push] setup failed',e); }
  }
  setup();
})(window);
