
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

function textResponse(body:string,status=200){
  return new Response(body,{status,headers:{"content-type":"text/plain; charset=utf-8","cache-control":"no-store"}});
}
function hexToBytes(hex:string){
  const clean=String(hex||"").trim().replace(/^0x/i,"");
  if(!clean || clean.length%2!==0 || !/^[0-9a-f]+$/i.test(clean)) throw new Error("INVALID_HEX");
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
function safeHexEqual(a:string,b:string){
  const x=String(a||"").toLowerCase(),y=String(b||"").toLowerCase();
  if(x.length!==y.length)return false;
  let diff=0;
  for(let i=0;i<x.length;i++)diff|=x.charCodeAt(i)^y.charCodeAt(i);
  return diff===0;
}
function pemToDer(pem:string){
  const body=pem.replace(/\\n/g,"\n").replace(/-----BEGIN PUBLIC KEY-----/g,"").replace(/-----END PUBLIC KEY-----/g,"").replace(/\s+/g,"");
  const bin=atob(body);
  const out=new Uint8Array(bin.length);
  for(let i=0;i<bin.length;i++)out[i]=bin.charCodeAt(i);
  return out;
}
function readDerLength(bytes:Uint8Array,offset:number){
  let len=bytes[offset++];
  if((len&0x80)===0)return {len,offset};
  const n=len&0x7f;
  if(n<1||n>4)throw new Error("ECDSA_DER_LENGTH");
  len=0;
  for(let i=0;i<n;i++)len=(len<<8)|bytes[offset++];
  return {len,offset};
}
function derEcdsaToRaw(sig:Uint8Array,size=32){
  let o=0;
  if(sig[o++]!==0x30)throw new Error("ECDSA_DER_SEQUENCE");
  const seq=readDerLength(sig,o);o=seq.offset;
  if(sig[o++]!==0x02)throw new Error("ECDSA_DER_R");
  const rl=readDerLength(sig,o);o=rl.offset;
  let r=sig.slice(o,o+rl.len);o+=rl.len;
  if(sig[o++]!==0x02)throw new Error("ECDSA_DER_S");
  const sl=readDerLength(sig,o);o=sl.offset;
  let s=sig.slice(o,o+sl.len);
  while(r.length>size&&r[0]===0)r=r.slice(1);
  while(s.length>size&&s[0]===0)s=s.slice(1);
  if(r.length>size||s.length>size)throw new Error("ECDSA_DER_INTEGER_SIZE");
  const raw=new Uint8Array(size*2);
  raw.set(r,size-r.length);
  raw.set(s,size+(size-s.length));
  return raw;
}
async function verifyEcdsa(message:string,signatureHex:string,keyId:string){
  const pem=Deno.env.get("CARDPAY_ECDSA_PUBKEY_"+keyId)||"";
  if(!pem)throw new Error("CARDPAY_ECDSA_PUBLIC_KEY_MISSING");
  const curve=Deno.env.get("CARDPAY_ECDSA_CURVE")||"P-256";
  const key=await crypto.subtle.importKey("spki",pemToDer(pem),{name:"ECDSA",namedCurve:curve},false,["verify"]);
  const rawSig=derEcdsaToRaw(hexToBytes(signatureHex),32);
  return await crypto.subtle.verify({name:"ECDSA",hash:"SHA-256"},key,rawSig,new TextEncoder().encode(message));
}
function amountToCents(v:string){
  if(!/^\d+(?:\.\d{1,2})?$/.test(v))throw new Error("INVALID_AMOUNT");
  const [w,f=""]=v.split(".");
  return Number(w)*100+Number((f+"00").slice(0,2));
}
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
async function readParams(req:Request){
  const u=new URL(req.url);
  const p=new URLSearchParams(u.search);
  if(req.method==="POST"){
    const ct=req.headers.get("content-type")||"";
    if(ct.includes("application/x-www-form-urlencoded")){
      const body=new URLSearchParams(await req.text());
      for(const [k,v] of body)p.set(k,v);
    }
  }
  return p;
}
function redirectUrl(status:string,vs:string){
  const configured=Deno.env.get("CARDPAY_APP_RETURN_URL")||"https://connectsportspro.com/cennik/";
  if(!configured)return "";
  const u=new URL(configured);
  u.searchParams.set("payment",status);
  if(vs)u.searchParams.set("vs",vs);
  return u.toString();
}

Deno.serve(async(req:Request)=>{
  if(!["GET","POST"].includes(req.method))return textResponse("GET or POST only",405);

  const enabled=(Deno.env.get("CARDPAY_ENABLED")||"").toLowerCase()==="true";
  const keyHex=Deno.env.get("CARDPAY_HMAC_KEY_HEX")||"";
  if(!enabled||!keyHex)return textResponse("CardPay nie je aktivovaný.",503);

  try{
    const p=await readParams(req);
    const AMT=String(p.get("AMT")||"");
    const CURR=String(p.get("CURR")||"");
    const VS=String(p.get("VS")||"");
    const RES=String(p.get("RES")||"");
    const AC=String(p.get("AC")||"");
    const TID=String(p.get("TID")||"");
    const TIMESTAMP=String(p.get("TIMESTAMP")||"");
    const HMAC=String(p.get("HMAC")||"");
    const ECDSA_KEY=String(p.get("ECDSA_KEY")||"");
    const ECDSA=String(p.get("ECDSA")||"");

    if(!AMT||!CURR||!VS||!RES||!TIMESTAMP||!HMAC||!ECDSA_KEY||!ECDSA){
      return textResponse("Neúplná odpoveď CardPay.",400);
    }

    const hmacString=AMT+CURR+VS+RES+AC+TID+TIMESTAMP;
    const expected=await hmacSha256(hmacString,keyHex);
    if(!safeHexEqual(expected,HMAC))return textResponse("Neplatný HMAC podpis CardPay.",403);

    const ecdsaString=hmacString+HMAC;
    const ecdsaOk=await verifyEcdsa(ecdsaString,ECDSA,ECDSA_KEY);
    if(!ecdsaOk)return textResponse("Neplatný ECDSA podpis CardPay.",403);

    if(CURR!=="978")return textResponse("Nepodporovaná mena.",400);
    if(!/^\d{1,10}$/.test(VS))return textResponse("Neplatný variabilný symbol.",400);

    const result=await rpc("csp_finalize_cardpay_order",{
      p_variable_symbol:Number(VS),
      p_amount_cents:amountToCents(AMT),
      p_currency:"EUR",
      p_result:RES,
      p_auth_code:AC,
      p_tid:TID,
      p_provider_timestamp:TIMESTAMP,
      p_ecdsa_key:ECDSA_KEY,
      p_metadata:{
        cardpayVerified:true,
        hmacVerified:true,
        ecdsaVerified:true
      }
    });

    const ok=String(RES).toUpperCase()==="OK"&&String(result?.status||"").toLowerCase()==="paid";
    const target=redirectUrl(ok?"success":"failed",VS);
    if(target)return Response.redirect(target,303);
    return textResponse(ok?"Platba bola potvrdená.":"Platba nebola úspešná.",ok?200:402);
  }catch(e){
    console.error("CARDPAY_RETURN_ERROR",e instanceof Error?e.message:String(e));
    return textResponse("Platbu sa nepodarilo bezpečne overiť.",500);
  }
});
