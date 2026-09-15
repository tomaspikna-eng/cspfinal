const PROJECT_ID='connectsportpro';
const PROJECT_NUMBER='36251906942';
const POOL_ID='vercel';
const PROVIDER_ID='vercel';
const SERVICE_ACCOUNT='csp-translation@connectsportpro.iam.gserviceaccount.com';
const CLOUD_SCOPE='https://www.googleapis.com/auth/cloud-platform';
const TIMEOUT_MS=20000;
const REPO='https://raw.githubusercontent.com/tomaspikna-eng/cspfinal/main/assets';
const SUPPORTED={cs:'Čeština',de:'Deutsch',pl:'Polski',ru:'Русский'};

async function fetchWithTimeout(url,options={}){const c=new AbortController();const t=setTimeout(()=>c.abort(),TIMEOUT_MS);try{return await fetch(url,{...options,signal:c.signal});}finally{clearTimeout(t);}}
function getOidcToken(req){const h=req.headers['x-vercel-oidc-token'];return Array.isArray(h)?(h[0]||''):(h||process.env.VERCEL_OIDC_TOKEN||'');}
async function getGoogleAccessToken(token){
  const audience=`//iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}`;
  const body=new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:token-exchange',audience,scope:CLOUD_SCOPE,requested_token_type:'urn:ietf:params:oauth:token-type:access_token',subject_token:token,subject_token_type:'urn:ietf:params:oauth:token-type:jwt'});
  const r=await fetchWithTimeout('https://sts.googleapis.com/v1/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body});
  const s=await r.json(); if(!r.ok||!s.access_token) throw new Error(`STS failed: ${s.error_description||s.error||r.status}`);
  const url=`https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${encodeURIComponent(SERVICE_ACCOUNT)}:generateAccessToken`;
  const ir=await fetchWithTimeout(url,{method:'POST',headers:{Authorization:`Bearer ${s.access_token}`,'Content-Type':'application/json'},body:JSON.stringify({scope:[CLOUD_SCOPE],lifetime:'3600s'})});
  const i=await ir.json(); if(!ir.ok||!i.accessToken) throw new Error(`Impersonation failed: ${i.error?.message||ir.status}`); return i.accessToken;
}
async function translateBatch(token,texts,source,target){
  if(!texts.length) return [];
  const url=`https://translation.googleapis.com/v3/projects/${PROJECT_ID}/locations/global:translateText`;
  const r=await fetchWithTimeout(url,{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json; charset=utf-8'},body:JSON.stringify({contents:texts,sourceLanguageCode:source,targetLanguageCode:target,mimeType:'text/plain'})});
  const j=await r.json(); if(!r.ok) throw new Error(`Translate failed: ${j.error?.message||r.status}`); return (j.translations||[]).map(x=>x.translatedText||'');
}
async function translateAll(token,texts,source,target){const out=[];for(let i=0;i<texts.length;i+=40)out.push(...await translateBatch(token,texts.slice(i,i+40),source,target));return out;}

export default async function handler(req,res){
  if(req.method!=='GET') return res.status(405).json({error:'Method not allowed'});
  const lang=String(req.query.lang||'').toLowerCase();
  if(!SUPPORTED[lang]) return res.status(400).json({error:'Unsupported lang'});
  try{
    const oidc=getOidcToken(req); if(!oidc) return res.status(503).json({error:'OIDC unavailable'});
    const [enR,targetR]=await Promise.all([
      fetchWithTimeout(`${REPO}/csp-locale-en.json`,{cache:'no-store'}),
      fetchWithTimeout(`${REPO}/csp-locale-${lang}.json`,{cache:'no-store'})
    ]);
    if(!enR.ok||!targetR.ok) throw new Error(`Locale fetch failed: EN ${enR.status}, ${lang.toUpperCase()} ${targetR.status}`);
    const en=await enR.json(); const target=await targetR.json(); const token=await getGoogleAccessToken(oidc);
    const keys=Object.keys(en.translations||{});
    const missing=keys.filter(k=>!(target.translations&&typeof target.translations[k]==='string'&&target.translations[k].trim()));
    const translatedMissing=await translateAll(token,missing,'sk',lang);
    const map=new Map(missing.map((k,i)=>[k,translatedMissing[i]||k]));
    const translations={}; keys.forEach(k=>{translations[k]=target.translations?.[k]||map.get(k)||k;});

    const enPatterns=Array.isArray(en.patterns)?en.patterns:[];
    const targetPatternMap=new Map((Array.isArray(target.patterns)?target.patterns:[]).map(p=>[p.source,p]));
    const missingPatterns=enPatterns.filter(p=>!targetPatternMap.has(p.source));
    const translatedPatternTargets=await translateAll(token,missingPatterns.map(p=>p.target||''),'en',lang);
    const patternTranslations=new Map(missingPatterns.map((p,i)=>[p.source,translatedPatternTargets[i]||p.target||'']));
    const patterns=enPatterns.map(p=>{const existing=targetPatternMap.get(p.source);return existing||{source:p.source,...(p.flags?{flags:p.flags}:{}),target:patternTranslations.get(p.source)||p.target||''};});

    const payload={locale:lang,name:target.name||SUPPORTED[lang],version:'2026-09-15',translations,patterns,_audit:{canonical_keys:keys.length,missing_keys_filled:missing.length,canonical_patterns:enPatterns.length,missing_patterns_filled:missingPatterns.length}};
    res.setHeader('Content-Type','application/json; charset=utf-8'); res.setHeader('Cache-Control','no-store'); res.status(200).send(JSON.stringify(payload,null,2));
  }catch(e){console.error('[build-locale-audit]',e);res.status(500).json({error:String(e?.message||e)});}
}
