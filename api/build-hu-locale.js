const PROJECT_ID='connectsportpro';
const PROJECT_NUMBER='36251906942';
const POOL_ID='vercel';
const PROVIDER_ID='vercel';
const SERVICE_ACCOUNT='csp-translation@connectsportpro.iam.gserviceaccount.com';
const CLOUD_SCOPE='https://www.googleapis.com/auth/cloud-platform';
const TIMEOUT_MS=20000;
const EN_LOCALE_URL='https://raw.githubusercontent.com/tomaspikna-eng/cspfinal/main/assets/csp-locale-en.json';
const HU_LOCALE_URL='https://raw.githubusercontent.com/tomaspikna-eng/cspfinal/main/assets/csp-locale-hu.json';

const OVERRIDES={
  'Vývoj hodnotenia':'Értékelés alakulása',
  'Respekty':'Tiszteletek',
  'Reprezentant':'Képviselő',
  'Krátky medailón':'Rövid bemutatkozás',
  'Vyber zväz.':'Válassz szövetséget.',
  'Nahrávam pozadie...':'Háttér feltöltése...',
  'Pozadie sa nepodarilo nahrať.':'A háttér feltöltése sikertelen.',
  'Pripoj sa':'Csatlakozz',
  'k':'a',
  'Začneš s plánom':'Ezzel a csomaggal kezdesz:',
  '— zdarma navždy.':'— örökre ingyen.',
  'podmienkami':'feltételekkel',
  'ochranou súkromia':'adatvédelmi szabályzattal',
  'ŠTÁT — VŠETKY':'ORSZÁG — ÖSSZES',
  'MESTO — VŠETKY':'VÁROS — ÖSSZES',
  'ŠPORT — VŠETKY':'SPORT — ÖSSZES',
  'Vypnutá':'Kikapcsolva',
  'Zapnutá':'Bekapcsolva',
  'Turnaj':'Verseny',
  'Počet hráčov na stole':'Játékosok száma asztalonként',
  'Navrhnutý počet stolov':'Javasolt asztalszám',
  'Počet postupujúcich':'Továbbjutók száma',
  'Generovať stoly':'Asztalok generálása',
  'Vygenerovať finálový stôl':'Döntőasztal generálása',
  'Turnaj je ukončený':'A verseny befejeződött',
  'Turnaj prebieha':'A verseny folyamatban van',
  'Priebeh':'Élő állás',
  'Priebeh turnaja':'A verseny menete',
  'Pavúk':'Ágrajz',
  'Hlavný pavúk':'Főág',
  '✓ Phase 2 · Hlavný pavúk':'✓ 2. fázis · Főág',
  'NÁVRH':'VÁZLAT',
  'UKONČENÝ':'BEFEJEZVE',
  'Turnaj bol ukončený a uložený do histórie.':'A verseny befejeződött és bekerült az előzményekbe.',
  'Turnajové stanovisko':'Versenyállomás',
  'QR zápasu':'Mérkőzés QR-kódja',
  'Trvalé priradenie tabletu ku stanovisku':'A tablet állandó hozzárendelése az állomáshoz',
  'Najprv priraď zápas ku konkrétnemu stanovisku.':'Először rendeld a mérkőzést egy konkrét állomáshoz.',
  'QR tabletu sa nepodarilo vytvoriť.':'A tablet QR-kódját nem sikerült létrehozni.',
  'Stanoviská vytvorené ✓':'Állomások létrehozva ✓',
  'CONNECT SPORTS PRO · TOURNAMENT TABLET':'CONNECT SPORTS PRO · VERSENY TABLET',
  'SMART AUTO':'SMART AUTO',
  'Stanovisko':'Állomás',
  'PRIPÁJANIE':'CSATLAKOZÁS',
  'PRIPRAVENÍ':'KÉSZ',
  'VOĽNÉ':'SZABAD',
  'Nový frame':'Új frame',
  'Nový set':'Új szett',
  'Race to':'Race to',
  'Body na frame':'Pontok frame-enként',
  'Body na set':'Pontok szettenként',
  'Double out':'Double out',
  'Finiš dvojkou':'Double out befejezés',
  'Rozstrel':'Kezdés',
  'Striedavý rozstrel':'Váltott kezdés',
  'Na rade':'Következik',
  'Štart':'Indítás',
  'Aktuálny run —':'Aktuális sorozat —',
  'Aktuálny run':'Aktuális sorozat',
  'Zapísať ✓':'Rögzítés ✓',
  'Mimo (0)':'Mellé (0)',
  'Univerzál':'Egyéni',
  'Tablet je pevne priradený k tomuto stanovisku':'A tablet végleg ehhez az állomáshoz van rendelve',
  'Stanovisko sa nepodarilo načítať.':'Az állomást nem sikerült betölteni.',
  'Nasadenie':'Kiemelés',
  'Prevádzka':'Üzemeltetés',
  'Správa':'Kezelés',
  'Obsadený':'Foglalt',
  'Voľný':'Szabad',
  'Voľné':'Szabad',
  'Obsadené':'Foglalt',
  'Mimo prevádzky':'Üzemen kívül',
  'Voľné — rezervovať':'Szabad — foglalás',
  'Pridať na plochu':'Hozzáadás a kezdőképernyőhöz',
  'Koncept':'Vázlat',
  'H Nadpis':'H Címsor',
  'URL slug':'URL slug',
  'Obálka':'Borítókép',
  'Koncepty':'Vázlatok',
  'Všetky stavy':'Minden állapot',
  'Nahrávam obálku…':'Borítókép feltöltése…',
  'Obálka nahraná ✓':'Borítókép feltöltve ✓',
  'Stiahnuť':'Visszavonás',
  'Vybrať Pro':'Pro kiválasztása',
  'plán':'csomag',
  'Informácie':'Információk',
  'Ochrana osobných údajov':'Adatvédelmi irányelvek',
  'Športy':'Sportok',
  'Followers, respekty, share výsledkov. Keď niečo dokážeš, tvoja komunita to vidí. Keď tvoj kamoš pokorí osobný rekord, vieš to prvý.':'Követők, tiszteletek, eredménymegosztás. Ha elérsz valamit, a közösséged látja. Ha a barátod személyes rekordot dönt, te az elsők között tudod meg.',
  'Vlastné turnaje a udalosti':'Saját versenyek és események',
  'Člen od —':'Tag ettől: —',
  'Napr. Ján Novák Peter Kováč Martin Horváth':'Pl. Ján Novák Peter Kováč Martin Horváth',
  'napr. Kurt, Dráha A, Squashová miestnosť':'pl. Pálya, A sáv, squash terem',
  'Napr. názov "Kurt" + počet 3 → Kurt 1, Kurt 2, Kurt 3':'Pl. „Pálya” + 3 → Pálya 1, Pálya 2, Pálya 3',
  'Rezervovať':'Foglalás',
  'Nájdite':'Keresse meg',
  'Kliknite':'Kattintson',
  'Súhlas':'Hozzájárulás',
  'Súhlasu':'Hozzájárulás',
  'DOPLNIŤ':'KIEGÉSZÍTENDŐ',
  'DOPLNIŤ: IČO':'KIEGÉSZÍTENDŐ: Cégjegyzékszám',
  'Vypadáva':'Kiesik',
  'Ukončiť stôl':'Asztal lezárása',
  'Prehánky':'Záporok',
  'Kolky':'Tekézés',
  'vas@email.sk':'te@email.hu'
};

const PATTERN_TARGETS={
  '^Stôl (\\d+)$':'Asztal $1',
  '^Šípky (\\d+)$':'Darts $1',
  '^(\\d+) hráči$':'$1 játékos',
  '^(\\d+) hráčov$':'$1 játékos',
  '^(\\d+) hráč$':'$1 játékos',
  '^Kolo (\\d+)$':'$1. forduló',
  '^Frame (\\d+)$':'Frame $1',
  '^Sledovatelia · (\\d+)$':'Követők · $1',
  '^Rezervácia (.+) o (.+) — potvrdenie pošleme e-mailom \\(ULTRA\\)\\.$':'Foglalás: $1, $2 — a visszaigazolást e-mailben küldjük (ULTRA).',
  '^(.+) športovisko$':'$1 sportlétesítmény',
  '^(.+) športoviská$':'$1 sportlétesítmény',
  '^(.+) športovísk$':'$1 sportlétesítmény',
  '^(.+) vyhral zápas!$':'$1 megnyerte a mérkőzést!',
  '^(.+) vyhral zápas \\(Race to (.+)\\)$':'$1 megnyerte a mérkőzést (Race to $2)',
  '^Turnajový zápas načítaný: (.+) vs (.+)$':'Versenymérkőzés betöltve: $1 vs $2',
  '^Zápas je už uzavretý: (.+)$':'A mérkőzés már lezárult: $1',
  '^Rezervácia potvrdená — (.+)$':'Foglalás megerősítve — $1',
  '^Naozaj odstrániť "(.+)"\\?$':'Biztosan eltávolítod: „$1”?',
  '^Vypadáva: (.+)$':'Kiesik: $1',
  '^Na stole „(.+)“ označ aspoň jedného vypadávajúceho hráča\\.$':'Az „$1” asztalnál jelölj meg legalább egy kieső játékost.',
  '^Zo stola „(.+)“ musí postúpiť aspoň jeden hráč\\.$':'Az „$1” asztaltól legalább egy játékosnak tovább kell jutnia.',
  '^(.+) hráčov · (.+)$':'$1 játékos · $2',
  '^(.+)\\. kolo$':'$1. forduló',
  '^Loser kolo (.+)$':'Vesztes ág $1. forduló',
  '^Pozri si profil (.+) na Connect Sports Pro\\.$':'Nézd meg $1 profilját a Connect Sports Pro oldalon.',
  '^⚠ Stav (.+) sa nepodarilo synchronizovať$':'⚠ A(z) $1 állapot szinkronizálása sikertelen',
  '^(.+) dosiahol cieľ (.+)$':'$1 elérte a célt: $2',
  '^(.+) — séria (.+) \\(frame (.+)\\)$':'$1 — sorozat $2 (frame $3)',
  '^Cieľ (.+) b\\. · Race to (.+)$':'Cél: $1 pont · Race to $2',
  '^Nový (.+) (.+)$':'Új $1 $2',
  '^(.+) športovísk pridaných\\.$':'$1 sportlétesítmény hozzáadva.',
  '^Šípky (.+)$':'Darts $1',
  '^Skupinová fáza ukončená — (.+) pavúk je pripravený ✓$':'A csoportkör befejeződött — a(z) $1 ág készen áll ✓'
};

async function fetchWithTimeout(url,options={}){const c=new AbortController();const t=setTimeout(()=>c.abort(),TIMEOUT_MS);try{return await fetch(url,{...options,signal:c.signal});}finally{clearTimeout(t);}}
function getOidcToken(req){const h=req.headers['x-vercel-oidc-token'];return Array.isArray(h)?(h[0]||''):(h||process.env.VERCEL_OIDC_TOKEN||'');}
async function getGoogleAccessToken(token){const audience=`//iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}`;const body=new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:token-exchange',audience,scope:CLOUD_SCOPE,requested_token_type:'urn:ietf:params:oauth:token-type:access_token',subject_token:token,subject_token_type:'urn:ietf:params:oauth:token-type:jwt'});const r=await fetchWithTimeout('https://sts.googleapis.com/v1/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body});const s=await r.json();if(!r.ok||!s.access_token)throw new Error(`STS failed: ${s.error_description||s.error||r.status}`);const url=`https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${encodeURIComponent(SERVICE_ACCOUNT)}:generateAccessToken`;const ir=await fetchWithTimeout(url,{method:'POST',headers:{Authorization:`Bearer ${s.access_token}`,'Content-Type':'application/json'},body:JSON.stringify({scope:[CLOUD_SCOPE],lifetime:'3600s'})});const i=await ir.json();if(!ir.ok||!i.accessToken)throw new Error(`Impersonation failed: ${i.error?.message||ir.status}`);return i.accessToken;}
async function translateBatch(token,texts){if(!texts.length)return[];const url=`https://translation.googleapis.com/v3/projects/${PROJECT_ID}/locations/global:translateText`;const r=await fetchWithTimeout(url,{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json; charset=utf-8'},body:JSON.stringify({contents:texts,sourceLanguageCode:'sk',targetLanguageCode:'hu',mimeType:'text/plain'})});const j=await r.json();if(!r.ok)throw new Error(`Translate failed: ${j.error?.message||r.status}`);return(j.translations||[]).map(x=>x.translatedText||'');}
async function translateAll(token,texts){const out=[];for(let i=0;i<texts.length;i+=40)out.push(...await translateBatch(token,texts.slice(i,i+40)));return out;}

export default async function handler(req,res){
  if(req.method!=='GET')return res.status(405).json({error:'Method not allowed'});
  try{
    const oidc=getOidcToken(req);if(!oidc)return res.status(503).json({error:'OIDC unavailable'});
    const [er,hr]=await Promise.all([fetchWithTimeout(EN_LOCALE_URL,{cache:'no-store'}),fetchWithTimeout(HU_LOCALE_URL,{cache:'no-store'})]);
    if(!er.ok)throw new Error(`EN locale ${er.status}`);
    const en=await er.json();const hu=hr.ok?await hr.json():{translations:{},patterns:[]};const access=await getGoogleAccessToken(oidc);
    const canonicalKeys=Object.keys(en.translations||{});const missing=canonicalKeys.filter(k=>!(hu.translations&&typeof hu.translations[k]==='string'&&hu.translations[k].trim()));const mt=await translateAll(access,missing);const byKey=new Map(missing.map((k,i)=>[k,mt[i]||k]));
    const generated={};canonicalKeys.forEach(k=>{generated[k]=OVERRIDES[k]||hu.translations?.[k]||byKey.get(k)||k;});Object.keys(hu.translations||{}).filter(k=>!Object.prototype.hasOwnProperty.call(generated,k)).forEach(k=>{generated[k]=OVERRIDES[k]||hu.translations[k];});
    Object.entries(OVERRIDES).forEach(([k,v])=>{if(Object.prototype.hasOwnProperty.call(generated,k)||Object.prototype.hasOwnProperty.call(en.translations||{},k))generated[k]=v;});
    const patterns=(Array.isArray(en.patterns)?en.patterns:[]).map(p=>({source:p.source,...(p.flags?{flags:p.flags}:{}),target:PATTERN_TARGETS[p.source]||p.target||''}));
    const payload={locale:'hu',name:'Magyar',version:'2026-09-15',translations:generated,patterns};
    res.setHeader('Content-Type','application/json; charset=utf-8');res.setHeader('Cache-Control','no-store');res.status(200).send(JSON.stringify(payload,null,2));
  }catch(error){console.error('[build-hu-locale]',error);res.status(500).json({error:String(error?.message||error)});}
}
