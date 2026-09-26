
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const CORS={
  "Access-Control-Allow-Origin":"*",
  "Access-Control-Allow-Headers":"authorization, apikey, content-type",
  "Access-Control-Allow-Methods":"POST, OPTIONS"
};

function json(data:unknown,status=200){
  return new Response(JSON.stringify(data),{status,headers:{...CORS,"content-type":"application/json; charset=utf-8","cache-control":"no-store"}});
}
function decodeJwt(token:string){
  try{
    const p=token.split(".")[1];
    const b64=p.replace(/-/g,"+").replace(/_/g,"/");
    const padded=b64+"=".repeat((4-b64.length%4)%4);
    return JSON.parse(atob(padded));
  }catch{return null}
}
function hexToBytes(hex:string){
  const clean=hex.trim().replace(/^0x/i,"");
  if(!/^[0-9a-f]{128}$/i.test(clean))throw new Error("CARDPAY_HMAC_KEY_HEX_INVALID");
  const out=new Uint8Array(clean.length/2);
  for(let i=0;i<out.length;i++)out[i]=parseInt(clean.slice(i*2,i*2+2),16);
  return out;
}
function bytesToHex(bytes:ArrayBuffer){
  return [...new Uint8Array(bytes)].map(b=>b.toString(16).padStart(2,"0")).join("");
}
async function hmacSha256(message:string,keyHex:string){
  const key=await crypto.subtle.importKey("raw",hexToBytes(keyHex),{name:"HMAC",hash:"SHA-256"},false,["sign"]);
  return bytesToHex(await crypto.subtle.sign("HMAC",key,new TextEncoder().encode(message)));
}
function utcTimestamp(d=new Date()){
  const p=(n:number)=>String(n).padStart(2,"0");
  return p(d.getUTCDate())+p(d.getUTCMonth()+1)+d.getUTCFullYear()+p(d.getUTCHours())+p(d.getUTCMinutes())+p(d.getUTCSeconds());
}
function clientIp(req:Request){
  const raw=req.headers.get("x-forwarded-for")||req.headers.get("cf-connecting-ip")||req.headers.get("x-real-ip")||"";
  return raw.split(",")[0].trim().slice(0,45);
}
function cardPayName(v:unknown,fallback:string){
  const cleaned=String(v??"")
    .normalize("NFD").replace(/[\u0300-\u036f]/g,"")
    .replace(/[^0-9A-Za-z ._@-]+/g," ")
    .replace(/\s+/g," ").trim().slice(0,64);
  if(cleaned)return cleaned;
  return fallback.normalize("NFD").replace(/[\u0300-\u036f]/g,"").replace(/[^0-9A-Za-z ._@-]+/g," ").trim().slice(0,64);
}
function notificationEmail(v:unknown){
  const s=String(v??"").trim();
  if(s.length>50)return "";
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s)?s:"";
}
function amountString(cents:number){return (cents/100).toFixed(2)}
async function rpc(name:string,payload:Record<string,unknown>){
  const url=Deno.env.get("SUPABASE_URL")||"";
  const secretJson=Deno.env.get("SUPABASE_SECRET_KEYS");
  const key=secretJson?JSON.parse(secretJson)["default"]:"";
  if(!url||!key)throw new Error("SUPABASE_ADMIN_NOT_CONFIGURED");
  const r=await fetch(url+"/rest/v1/rpc/"+name,{
    method:"POST",
    headers:{apikey:key,Authorization:"Bearer "+key,"content-type":"application/json"},
    body:JSON.stringify(payload)
  });
  const raw=await r.text();
  if(!r.ok)throw new Error(name+" "+r.status+": "+raw.slice(0,300));
  try{return raw?JSON.parse(raw):null}catch{return raw}
}

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:CORS});
  if(req.method!=="POST")return json({error:"POST only"},405);

  const enabled=(Deno.env.get("CARDPAY_ENABLED")||"").toLowerCase()==="true";
  const mid=Deno.env.get("CARDPAY_MID")||"";
  const keyHex=Deno.env.get("CARDPAY_HMAC_KEY_HEX")||"";
  const gateway=Deno.env.get("CARDPAY_GATEWAY_URL")||"https://moja.tatrabanka.sk/cgi-bin/e-commerce/start/cardpay";
  const supabaseUrl=Deno.env.get("SUPABASE_URL")||"";
  const configValid=/^\d{3,5}$/.test(mid)&&/^[0-9a-f]{128}$/i.test(keyHex)&&!!supabaseUrl;
  const configured=enabled&&configValid;

  let body:any={};
  try{body=await req.json()}catch{}
  if(body?.action==="status"){
    return json({
      ok:true,
      provider:"cardpay",
      app:"Connect Sports Pro",
      enabled,
      configured,
      liveReady:configured
    });
  }

  if(!configured){
    return json({
      ok:false,
      error:"CARDPAY_NOT_CONFIGURED",
      userMessage:"CardPay je technicky pripravený, ale čaká na MID a 64-bajtový bezpečnostný kľúč od Tatra banky."
    },503);
  }

  const auth=req.headers.get("authorization")||"";
  const token=auth.toLowerCase().startsWith("bearer ")?auth.slice(7).trim():"";
  const claims=decodeJwt(token);
  const userId=String(claims?.sub||"");
  if(!userId)return json({error:"AUTH_REQUIRED",userMessage:"Najprv sa prihlás."},401);

  const productCode=String(body?.productCode||"").trim().slice(0,80);
  if(!productCode)return json({error:"PRODUCT_REQUIRED"},400);

  const order=await rpc("csp_create_cardpay_order",{
    p_user_id:userId,
    p_product_code:productCode
  });

  const amt=amountString(Number(order?.amountCents||0));
  const curr="978";
  const vs=String(order?.variableSymbol||"");
  const rurl=supabaseUrl+"/functions/v1/cardpay-return";
  const ipc=clientIp(req);
  if(!ipc)return json({error:"CLIENT_IP_MISSING",userMessage:"Nepodarilo sa zistiť IP adresu klienta."},400);

  const email=String(claims?.email||"");
  const meta=claims?.user_metadata||{};
  const name=cardPayName(meta?.display_name||meta?.full_name||meta?.name||email,"Connect Sports Pro");
  const rem=notificationEmail(email);
  const timestamp=utcTimestamp();

  const hmacString=mid+amt+curr+vs+rurl+ipc+name+rem+timestamp;
  const hmac=await hmacSha256(hmacString,keyHex);

  return json({
    ok:true,
    provider:"cardpay",
    orderId:order?.orderId,
    gatewayUrl:gateway,
    method:"POST",
    fields:{
      MID:mid,
      AMT:amt,
      CURR:curr,
      VS:vs,
      RURL:rurl,
      IPC:ipc,
      NAME:name,
      REM:rem,
      TIMESTAMP:timestamp,
      HMAC:hmac
    }
  });
});
