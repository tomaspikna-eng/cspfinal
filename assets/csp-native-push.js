(function(global){
  'use strict';

  var C=global.Capacitor;
  if(!C||!C.isNativePlatform||!C.isNativePlatform()) return;

  var P=C.Plugins&&C.Plugins.PushNotifications;
  if(!P||!global.cspAuth){
    console.warn('[csp-native-push] PushNotifications plugin is not available.');
    return;
  }

  var registeredToken=null;
  var pendingToken=null;
  var listenersBound=false;

  async function currentSession(){
    try{
      var s=await global.cspAuth.getSession();
      return s&&s.data&&s.data.session||null;
    }catch(_e){
      return null;
    }
  }

  async function saveToken(token){
    if(!token) return;
    pendingToken=token;

    var session=await currentSession();
    if(!session) return;
    if(token===registeredToken) return;

    var r=await global.cspAuth.client.rpc('register_push_device',{
      p_token:token,
      p_platform:'android',
      p_device_name:(navigator.userAgent||'Android').slice(0,180),
      p_app_version:'1.0.6'
    });

    if(r.error){
      console.error('[csp-native-push] register_push_device failed',r.error);
      return;
    }

    registeredToken=token;
    try{localStorage.setItem('csp_push_registered_token',token)}catch(_e){}
    console.info('[csp-native-push] device registered');
  }

  function actionUrl(ev){
    var d=ev&&ev.notification&&ev.notification.data||{};
    var u=String(d.action_url||'/');
    if(/^https:\/\/connectsportspro\.com\//.test(u)) return u;
    if(u.charAt(0)==='/') return u;
    return '/';
  }

  async function createChannels(){
    if(!P.createChannel) return;

    await P.createChannel({
      id:'csp_match_critical',
      name:'CSP zápasy',
      description:'Pripravený zápas, presun zápasu a súper pripravený',
      importance:5,
      visibility:1,
      sound:'default',
      vibration:true
    });

    await P.createChannel({
      id:'csp_general',
      name:'CSP upozornenia',
      description:'Kluby, turnaje, udalosti, sledované účty a ostatné upozornenia',
      importance:4,
      visibility:1,
      sound:'default',
      vibration:true
    });
  }

  async function bindListeners(){
    if(listenersBound) return;
    listenersBound=true;

    await P.addListener('registration',function(t){
      var token=t&&t.value;
      if(token) saveToken(token);
    });

    await P.addListener('registrationError',function(e){
      console.error('[csp-native-push] registration error',e);
    });

    await P.addListener('pushNotificationReceived',function(notification){
      global.dispatchEvent(new CustomEvent('csp:native-push',{
        detail:notification||{}
      }));
    });

    await P.addListener('pushNotificationActionPerformed',function(ev){
      var u=actionUrl(ev);
      if(/^https:\/\/connectsportspro\.com\//.test(u)) location.href=u;
      else location.href=u;
    });

    global.cspAuth.client.auth.onAuthStateChange(function(event){
      if(event==='SIGNED_IN'&&pendingToken) saveToken(pendingToken);
      if(event==='SIGNED_OUT') registeredToken=null;
    });
  }

  async function setup(){
    try{
      await createChannels();
      await bindListeners();

      var perm=await P.checkPermissions();
      if(perm.receive!=='granted') perm=await P.requestPermissions();
      if(perm.receive!=='granted'){
        console.info('[csp-native-push] notification permission not granted');
        return;
      }

      await P.register();
    }catch(e){
      console.error('[csp-native-push] setup failed',e);
    }
  }

  setup();
})(window);
