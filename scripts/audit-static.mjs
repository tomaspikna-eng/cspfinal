import fs from "node:fs";
import path from "node:path";
import {spawnSync} from "node:child_process";

const root=path.resolve(import.meta.dirname,"..");
const errors=[];
const warnings=[];

function walk(dir){
  return fs.readdirSync(dir,{withFileTypes:true}).flatMap(function(entry){
    if(entry.name===".git"||entry.name==="node_modules")return [];
    const full=path.join(dir,entry.name);
    return entry.isDirectory()?walk(full):[full];
  });
}
function fail(message){errors.push(message)}
function check(condition,message){if(!condition)fail(message)}
function read(rel){return fs.readFileSync(path.join(root,rel),"utf8")}

const files=walk(root);
const htmlFiles=files.filter(function(file){return file.endsWith(".html")});
const jsFiles=files.filter(function(file){return file.endsWith(".js")});

for(const file of jsFiles){
  const run=spawnSync(process.execPath,["--check",file],{encoding:"utf8"});
  if(run.status!==0)fail("JavaScript syntax: "+path.relative(root,file)+" — "+run.stderr.trim());
}

for(const file of htmlFiles){
  const html=fs.readFileSync(file,"utf8");
  let index=0;
  for(const match of html.matchAll(/<script([^>]*)>([\s\S]*?)<\/script>/gi)){
    const attrs=match[1]||"";
    const code=match[2]||"";
    if(/\bsrc\s*=|application\/ld\+json/i.test(attrs)||!code.trim())continue;
    index++;
    try{new Function(code)}
    catch(error){fail("Inline JavaScript: "+path.relative(root,file)+" #"+index+" — "+error.message)}
  }
  for(const match of html.matchAll(/(?:href|src)=["'](\/[^"'<>]*)["']/gi)){
    const raw=match[1];
    const pathname=raw.split(/[?#]/)[0];
    if(!pathname||pathname.startsWith("/api/"))continue;
    if(pathname==="/projektortv/"){
      warnings.push("Povolená výnimka: /projektortv/ nemá lokálnu route.");
      continue;
    }
    let decoded;
    try{decoded=decodeURIComponent(pathname)}
    catch(error){fail("Neplatná URL v "+path.relative(root,file)+": "+raw);continue}
    const local=path.join(root,decoded.replace(/^\/+/, ""));
    const target=path.extname(local)?local:path.join(local,"index.html");
    if(!fs.existsSync(target))fail("Chýbajúci interný cieľ v "+path.relative(root,file)+": "+raw);
  }
  check(/<link[^>]+rel=["'](?:shortcut )?icon["']/i.test(html),"Chýba favicon: "+path.relative(root,file));
  check(/<meta[^>]+name=["']description["']/i.test(html),"Chýba description: "+path.relative(root,file));
}

const allText=files
  .filter(function(file){return /\.(?:html|js|json|md|txt)$/i.test(file)})
  .map(function(file){return fs.readFileSync(file,"utf8")})
  .join("\n");

check(!allText.includes("@supabase@supabase"),"Poškodená Supabase CDN adresa.");
check(!/@supabase\/supabase-js@2(?!\.57\.4)/.test(allText),"Supabase CDN nie je pripnuté na 2.57.4.");
for(const file of htmlFiles){
  const html=fs.readFileSync(file,"utf8");
  for(const match of html.matchAll(/<script[^>]+src=["']https:\/\/(?:cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com)\/[^"']+["'][^>]*>/gi)){
    check(/\bintegrity=["']sha384-[^"']+["']/i.test(match[0]),"CDN skript nemá SHA-384 integritu: "+path.relative(root,file));
    check(/\bcrossorigin=["']anonymous["']/i.test(match[0]),"CDN skript nemá crossorigin=anonymous: "+path.relative(root,file));
  }
}
check(!/(?:email|kontakt)@connectsportspro\.com/.test(allText),"Nejednotná kontaktná adresa.");
check(!allText.includes("legacyCardGenerator"),"Zostal vypnutý legacy kartový generátor.");
check(!fs.existsSync(path.join(root,"translation-test.html")),"V produkcii zostal translation-test.html.");
check(!fs.existsSync(path.join(root,"assets/app.js")),"Zostal nepoužívaný assets/app.js.");
check(!fs.existsSync(path.join(root,"assets/csp-i18n.js")),"Zostala duplicitná i18n vrstva.");
check(!fs.existsSync(path.join(root,"csp-social.js")),"Zostal duplicitný koreňový csp-social.js.");
check(!files.some(function(file){return path.dirname(file)===root&&file.endsWith(".sql")}),"SQL súbory nesmú byť vo verejnom koreňovom priečinku.");
check(read("registracia/index.html").includes("/assets/csp-logo-full.png"),"Registrácia nepoužíva plné CSP logo.");
check(read("login/index.html").includes("returnTo")&&read("registracia/index.html").includes("returnTo"),"Chýba jednotný returnTo tok.");
check(read("cennik/index.html").includes("5,99")&&read("cennik/index.html").includes("9,99")&&read("cennik/index.html").includes("24,90"),"Cenník nemá aktuálne ceny.");
check(read("rebricky/index.html").includes("pro_plus"),"PRO+ chýba v správe rebríčkov.");
check(read("profil-ul/index.html").includes("pro_plus"),"PRO+ chýba v profile organizátora.");
check(read("turnament/index.html").includes("third_place_playoff")&&read("turnament/index.html").includes("Hra o tretie miesto"),"Chýba zápas o tretie miesto.");
check(read("vercel.json").includes("Content-Security-Policy"),"Chýba Content-Security-Policy.");
check(read("api/translate.js").includes("consume_translation_quota")&&read("api/translate.js").includes("Bearer"),"Prekladové API nemá auth alebo kvótu.");
check(fs.existsSync(path.join(root,"robots.txt"))&&fs.existsSync(path.join(root,"sitemap.xml")),"Chýba robots.txt alebo sitemap.xml.");
check(fs.existsSync(path.join(root,".github/workflows/quality.yml")),"Chýba CI kontrola.");

const migrationFiles=fs.readdirSync(path.join(root,"supabase/migrations")).filter(function(name){return name.endsWith(".sql")});
const versions=migrationFiles.map(function(name){return name.split("_")[0]});
check(migrationFiles.length===112,"Očakávaných 112 migrácií, nájdených "+migrationFiles.length+".");
check(new Set(versions).size===versions.length,"Duplicitná verzia migrácie.");

for(const warning of new Set(warnings))console.warn("WARN: "+warning);
if(errors.length){
  for(const error of errors)console.error("ERROR: "+error);
  console.error("\nKontrola zlyhala: "+errors.length+" problémov.");
  process.exit(1);
}
console.log("OK: "+htmlFiles.length+" HTML, "+jsFiles.length+" JS a "+migrationFiles.length+" migrácií prešlo kontrolou.");
