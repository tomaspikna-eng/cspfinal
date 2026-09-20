const CACHE='csp-club-manager-v3';
const CORE=[
  '/clubmanager/',
  '/clubmanager/dashboard/',
  '/clubmanager/personal/',
  '/clubmanager/reservations/',
  '/clubmanager/venues/',
  '/clubmanager/reports/',
  '/clubmanager/dochadzka/',
  '/clubmanager/bar/',
  '/clubmanager/assets/styles.css',
  '/clubmanager/assets/app.js',
  '/clubmanager/assets/config.js'
];

self.addEventListener('install',event=>{
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE).then(cache=>cache.addAll(CORE)).catch(()=>{})
  );
});

self.addEventListener('activate',event=>{
  event.waitUntil(
    caches.keys()
      .then(keys=>Promise.all(keys.filter(key=>key!==CACHE).map(key=>caches.delete(key))))
      .then(()=>self.clients.claim())
  );
});

self.addEventListener('fetch',event=>{
  if(event.request.method!=='GET') return;

  const url=new URL(event.request.url);
  if(url.origin!==self.location.origin) return;
  if(!url.pathname.startsWith('/clubmanager/')) return;

  event.respondWith(
    fetch(event.request).then(response=>{
      if(response.ok){
        const copy=response.clone();
        caches.open(CACHE).then(cache=>cache.put(event.request,copy)).catch(()=>{});
      }
      return response;
    }).catch(()=>caches.match(event.request))
  );
});