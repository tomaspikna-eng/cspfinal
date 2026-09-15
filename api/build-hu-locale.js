const PROJECT_ID='connectsportpro';
const PROJECT_NUMBER='36251906942';
const POOL_ID='vercel';
const PROVIDER_ID='vercel';
const SERVICE_ACCOUNT='csp-translation@connectsportpro.iam.gserviceaccount.com';
const CLOUD_SCOPE='https://www.googleapis.com/auth/cloud-platform';
const TIMEOUT_MS=20000;

async function fetchWithTimeout(url,options={}){
  const controller=new AbortController();
  const timer=setTimeout(()=>controller.abort(),TIMEOUT_MS);
  try{return await fetch(url,{...options,signal:controller.signal});}
  finally{clearTimeout(timer);}
}

function getOidcToken(req){
  const header=req.headers['x-vercel-oidc-token'];
  if(Array.isArray(header)) return header[0]||'';
  return header||process.env.VERCEL_OIDC_TOKEN||'';
}

async function getGoogleAccessToken(vercelOidcToken){
  const audience=`//iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL_ID}/providers/${PROVIDER_ID}`;
  const stsBody=new URLSearchParams({
    grant_type:'urn:ietf:params:oauth:grant-type:token-exchange',
    audience,
    scope:CLOUD_SCOPE,
    requested_token_type:'urn:ietf:params:oauth:token-type:access_token',
    subject_token:vercelOidcToken,
    subject_token_type:'urn:ietf:params:oauth:token-type:jwt'
  });
  const stsResponse=await fetchWithTimeout('https://sts.googleapis.com/v1/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:stsBody});
  const sts=await stsResponse.json();
  if(!stsResponse.ok||!sts.access_token) throw new Error(`STS failed: ${sts.error_description||sts.error||stsResponse.status}`);
  const url=`https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${encodeURIComponent(SERVICE_ACCOUNT)}:generateAccessToken`;
  const impersonationResponse=await fetchWithTimeout(url,{method:'POST',headers:{Authorization:`Bearer ${sts.access_token}`,'Content-Type':'application/json'},body:JSON.stringify({scope:[CLOUD_SCOPE],lifetime:'3600s'})});
  const impersonated=await impersonationResponse.json();
  if(!impersonationResponse.ok||!impersonated.accessToken) throw new Error(`Impersonation failed: ${impersonated.error?.message||impersonationResponse.status}`);
  return impersonated.accessToken;
}

async function translateBatch(accessToken,texts,source,target='hu'){
  if(!texts.length) return [];
  const url=`https://translation.googleapis.com/v3/projects/${PROJECT_ID}/locations/global:translateText`;
  const response=await fetchWithTimeout(url,{method:'POST',headers:{Authorization:`Bearer ${accessToken}`,'Content-Type':'application/json; charset=utf-8'},body:JSON.stringify({contents:texts,sourceLanguageCode:source,targetLanguageCode:target,mimeType:'text/plain'})});
  const result=await response.json();
  if(!response.ok) throw new Error(`Translate failed: ${result.error?.message||response.status}`);
  return (result.translations||[]).map(item=>item.translatedText||'');
}

async function translateAll(accessToken,texts,source){
  const out=[];
  for(let i=0;i<texts.length;i+=40){
    const batch=texts.slice(i,i+40);
    out.push(...await translateBatch(accessToken,batch,source));
  }
  return out;
}

export default async function handler(req,res){
  if(req.method!=='GET') return res.status(405).json({error:'Method not allowed'});
  try{
    const oidc=getOidcToken(req);
    if(!oidc) return res.status(503).json({error:'OIDC unavailable'});
    const origin=`https://${req.headers.host}`;
    const [enResponse,huResponse]=await Promise.all([
      fetchWithTimeout(`${origin}/assets/csp-locale-en.json`,{cache:'no-store'}),
      fetchWithTimeout(`${origin}/assets/csp-locale-hu.json`,{cache:'no-store'})
    ]);
    if(!enResponse.ok) throw new Error(`EN locale ${enResponse.status}`);
    const en=await enResponse.json();
    const hu=huResponse.ok?await huResponse.json():{translations:{},patterns:[]};
    const accessToken=await getGoogleAccessToken(oidc);
    const keys=Object.keys(en.translations||{});
    const missing=keys.filter(key=>!(hu.translations&&typeof hu.translations[key]==='string'&&hu.translations[key].trim()));
    const translatedMissing=await translateAll(accessToken,missing,'sk');
    const generated={};
    keys.forEach(key=>{generated[key]=hu.translations?.[key]||translatedMissing[missing.indexOf(key)]||key;});
    const enPatterns=Array.isArray(en.patterns)?en.patterns:[];
    const huPatternMap=new Map((Array.isArray(hu.patterns)?hu.patterns:[]).map(p=>[p.source,p.target]));
    const missingPatternTargets=enPatterns.filter(p=>!huPatternMap.has(p.source)).map(p=>p.target||'');
    const translatedPatternTargets=await translateAll(accessToken,missingPatternTargets,'en');
    let patternIndex=0;
    const patterns=enPatterns.map(p=>({
      source:p.source,
      ...(p.flags?{flags:p.flags}:{}),
      target:huPatternMap.get(p.source)||translatedPatternTargets[patternIndex++]||p.target||''
    }));
    const payload={locale:'hu',name:'Magyar',version:'2026-09-15',translations:generated,patterns};
    res.setHeader('Content-Type','application/json; charset=utf-8');
    res.setHeader('Cache-Control','no-store');
    res.status(200).send(JSON.stringify(payload,null,2));
  }catch(error){
    console.error('[build-hu-locale]',error);
    res.status(500).json({error:String(error?.message||error)});
  }
}
