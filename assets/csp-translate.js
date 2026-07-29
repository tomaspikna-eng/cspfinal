/* CONNECT SPORTS PRO — shared translation layer
   File: /assets/csp-translate.js */
(function(){
  'use strict';

  const SOURCE_LANGUAGE='sk';
  const SUPPORTED_LANGUAGES=new Set(['sk','cs','en','de','pl']);
  const LANGUAGE_STORAGE_KEY='csp_language';
  const CACHE_STORAGE_KEY='csp_translation_cache_v2';
  const API_ENDPOINT='/api/translate';
  const MAX_BATCH_SIZE=100;
  const SKIP_TAGS=new Set(['SCRIPT','STYLE','NOSCRIPT','CODE','PRE','TEXTAREA','OPTION','SVG','PATH','CANVAS','VIDEO','AUDIO']);
  const TRANSLATABLE_ATTRIBUTES=['title','aria-label','placeholder'];

  const originalTextNodes=new WeakMap();
  const originalAttributes=new WeakMap();
  let currentLanguage=SOURCE_LANGUAGE;
  let translating=false;
  let mutationObserver=null;
  let mutationTimer=null;

  function normalizeLanguage(value){
    const lang=String(value||'').trim().toLowerCase();
    if(lang==='cz') return 'cs';
    return SUPPORTED_LANGUAGES.has(lang)?lang:SOURCE_LANGUAGE;
  }

  function getSavedLanguage(){
    return normalizeLanguage(localStorage.getItem(LANGUAGE_STORAGE_KEY)||SOURCE_LANGUAGE);
  }

  function saveLanguage(language){
    try{localStorage.setItem(LANGUAGE_STORAGE_KEY,language);}catch(error){console.warn('[CSP translate] Unable to save language.',error);}
  }

  function loadCache(){
    try{
      const parsed=JSON.parse(localStorage.getItem(CACHE_STORAGE_KEY)||'{}');
      return parsed&&typeof parsed==='object'?parsed:{};
    }catch{return {};}
  }

  function saveCache(cache){
    try{localStorage.setItem(CACHE_STORAGE_KEY,JSON.stringify(cache));}catch(error){console.warn('[CSP translate] Unable to save cache.',error);}
  }

  function isTranslatableText(value){
    const text=String(value||'').trim();
    if(!text||!/[A-Za-zÀ-ž]/.test(text)) return false;
    if(/^(https?:\/\/|mailto:|tel:|www\.)/i.test(text)) return false;
    if(/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(text)) return false;
    if(/^(#[0-9a-f]{3,8}|[A-Z0-9_-]{12,}|[a-f0-9-]{24,})$/i.test(text)) return false;
    return true;
  }

  function shouldSkipElement(element){
    if(!element||SKIP_TAGS.has(element.tagName)) return true;
    if(element.closest("[data-no-translate],.notranslate,[translate='no']")) return true;
    if(element.closest('.brand,.brand-title,.brand-mark,.brand-mark-img,.csp-logo')) return true;
    if(element.closest("[data-player-name],[data-team-name],[data-club-name],[data-venue-name],[data-event-name],[data-tournament-name],[data-user-content],[contenteditable='true']")) return true;
    return false;
  }

  function collectTextNodes(root=document.body){
    const nodes=[];
    if(!root) return nodes;
    const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT,{acceptNode(node){
      const parent=node.parentElement;
      if(!parent||shouldSkipElement(parent)) return NodeFilter.FILTER_REJECT;
      if(!isTranslatableText(node.nodeValue)) return NodeFilter.FILTER_REJECT;
      return NodeFilter.FILTER_ACCEPT;
    }});
    let node;
    while((node=walker.nextNode())){
      if(!originalTextNodes.has(node)) originalTextNodes.set(node,node.nodeValue);
      nodes.push(node);
    }
    return nodes;
  }

  function collectAttributeItems(root=document.body){
    const items=[];
    if(!root||!root.querySelectorAll) return items;
    const selector=TRANSLATABLE_ATTRIBUTES.map(a=>`[${a}]`).join(',');
    root.querySelectorAll(selector).forEach(element=>{
      if(shouldSkipElement(element)) return;
      if(!originalAttributes.has(element)){
        originalAttributes.set(element,{
          title:element.getAttribute('title'),
          'aria-label':element.getAttribute('aria-label'),
          placeholder:element.getAttribute('placeholder')
        });
      }
      TRANSLATABLE_ATTRIBUTES.forEach(attribute=>{
        const value=element.getAttribute(attribute);
        if(isTranslatableText(value)) items.push({element,attribute});
      });
    });
    return items;
  }

  function restoreSourceLanguage(){
    collectTextNodes().forEach(node=>{
      const original=originalTextNodes.get(node);
      if(typeof original==='string') node.nodeValue=original;
    });
    collectAttributeItems().forEach(item=>{
      const original=originalAttributes.get(item.element)?.[item.attribute];
      if(original===null||original===undefined) item.element.removeAttribute(item.attribute);
      else item.element.setAttribute(item.attribute,original);
    });
    document.documentElement.lang=SOURCE_LANGUAGE;
  }

  async function requestTranslations(texts,targetLanguage){
    const response=await fetch(API_ENDPOINT,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({texts,source:SOURCE_LANGUAGE,target:targetLanguage})});
    const payload=await response.json().catch(()=>({}));
    if(!response.ok) throw new Error(payload.error||`Translation request failed with status ${response.status}.`);
    if(!Array.isArray(payload.translations)||payload.translations.length!==texts.length) throw new Error('Invalid translation response.');
    return payload.translations;
  }

  async function translateValues(values,targetLanguage){
    const cache=loadCache();
    cache[targetLanguage]=cache[targetLanguage]||{};
    const uniqueValues=[...new Set(values)];
    const missing=uniqueValues.filter(value=>!cache[targetLanguage][value]);
    for(let i=0;i<missing.length;i+=MAX_BATCH_SIZE){
      const batch=missing.slice(i,i+MAX_BATCH_SIZE);
      const translated=await requestTranslations(batch,targetLanguage);
      batch.forEach((source,index)=>{cache[targetLanguage][source]=translated[index]||source;});
      saveCache(cache);
    }
    return values.map(value=>cache[targetLanguage][value]||value);
  }

  function setSelectorValue(language){
    document.querySelectorAll('#cspLanguageSelect,[data-csp-language-select],.lang-select').forEach(select=>{
      if(select.tagName!=='SELECT') return;
      const match=Array.from(select.options).find(option=>normalizeLanguage(option.value)===language);
      if(match) select.value=match.value;
    });
  }

  async function applyLanguage(language,options={}){
    const target=normalizeLanguage(language);
    if(translating) return;
    translating=true;
    currentLanguage=target;
    document.body?.setAttribute('aria-busy','true');
    stopObserver();
    try{
      restoreSourceLanguage();
      if(target===SOURCE_LANGUAGE){
        saveLanguage(SOURCE_LANGUAGE);
        setSelectorValue(SOURCE_LANGUAGE);
        window.dispatchEvent(new CustomEvent('csp:language-changed',{detail:{language:SOURCE_LANGUAGE}}));
        return;
      }
      const textNodes=collectTextNodes();
      const attributeItems=collectAttributeItems();
      const textValues=textNodes.map(node=>String(originalTextNodes.get(node)||'').trim());
      const attributeValues=attributeItems.map(item=>String(originalAttributes.get(item.element)?.[item.attribute]||'').trim());
      const allValues=[...textValues,...attributeValues];
      if(allValues.length){
        const translated=await translateValues(allValues,target);
        textNodes.forEach((node,index)=>{
          const original=String(originalTextNodes.get(node)||node.nodeValue||'');
          const lead=original.match(/^\s*/)?.[0]||'';
          const trail=original.match(/\s*$/)?.[0]||'';
          node.nodeValue=lead+(translated[index]||original.trim())+trail;
        });
        attributeItems.forEach((item,index)=>{
          const value=translated[textValues.length+index];
          if(value) item.element.setAttribute(item.attribute,value);
        });
      }
      document.documentElement.lang=target;
      saveLanguage(target);
      setSelectorValue(target);
      window.dispatchEvent(new CustomEvent('csp:language-changed',{detail:{language:target}}));
    }catch(error){
      console.error('[CSP translate]',error);
      restoreSourceLanguage();
      currentLanguage=SOURCE_LANGUAGE;
      saveLanguage(SOURCE_LANGUAGE);
      setSelectorValue(SOURCE_LANGUAGE);
      if(!options.silent) console.warn('[CSP translate] Page remained in Slovak.');
    }finally{
      translating=false;
      document.body?.removeAttribute('aria-busy');
      startObserver();
    }
  }


  async function translateNewContent(root=document.body){
    if(translating||currentLanguage===SOURCE_LANGUAGE||!root) return;

    translating=true;
    document.body?.setAttribute('aria-busy','true');

    try{
      const textNodes=collectTextNodes(root).filter(node=>{
        const original=originalTextNodes.get(node);
        return typeof original==='string' && node.nodeValue===original;
      });

      const attributeItems=collectAttributeItems(root).filter(item=>{
        const original=originalAttributes.get(item.element)?.[item.attribute];
        return typeof original==='string' &&
          item.element.getAttribute(item.attribute)===original;
      });

      const textValues=textNodes.map(node=>
        String(originalTextNodes.get(node)||'').trim()
      );

      const attributeValues=attributeItems.map(item=>
        String(originalAttributes.get(item.element)?.[item.attribute]||'').trim()
      );

      const allValues=[...textValues,...attributeValues];
      if(!allValues.length) return;

      const translated=await translateValues(allValues,currentLanguage);

      textNodes.forEach((node,index)=>{
        const original=String(originalTextNodes.get(node)||node.nodeValue||'');
        const lead=original.match(/^\s*/)?.[0]||'';
        const trail=original.match(/\s*$/)?.[0]||'';
        node.nodeValue=lead+(translated[index]||original.trim())+trail;
      });

      attributeItems.forEach((item,index)=>{
        const value=translated[textValues.length+index];
        if(value) item.element.setAttribute(item.attribute,value);
      });

      document.documentElement.lang=currentLanguage;
    }catch(error){
      console.error('[CSP translate dynamic]',error);
    }finally{
      translating=false;
      document.body?.removeAttribute('aria-busy');
    }
  }

  function bindLanguageSelectors(){
    document.querySelectorAll('#cspLanguageSelect,[data-csp-language-select],.lang-select').forEach(select=>{
      if(select.tagName!=='SELECT'||select.dataset.cspTranslationBound==='1') return;
      select.dataset.cspTranslationBound='1';
      select.addEventListener('change',event=>applyLanguage(event.target.value));
    });
  }

  function stopObserver(){
    mutationObserver?.disconnect();
    if(mutationTimer){clearTimeout(mutationTimer);mutationTimer=null;}
  }

  function startObserver(){
    if(!document.body) return;
    stopObserver();

    mutationObserver=new MutationObserver(mutations=>{
      if(translating||currentLanguage===SOURCE_LANGUAGE) return;

      const roots=[];
      mutations.forEach(mutation=>{
        if(mutation.type==='characterData' && mutation.target?.parentElement){
          roots.push(mutation.target.parentElement);
        }

        if(mutation.type==='childList' && mutation.addedNodes?.length){
          mutation.addedNodes.forEach(node=>{
            if(node.nodeType===Node.ELEMENT_NODE) roots.push(node);
            else if(node.nodeType===Node.TEXT_NODE && node.parentElement) roots.push(node.parentElement);
          });
        }
      });

      if(!roots.length) return;

      if(mutationTimer) clearTimeout(mutationTimer);
      mutationTimer=setTimeout(async()=>{
        bindLanguageSelectors();

        for(const root of [...new Set(roots)]){
          await translateNewContent(root);
        }
      },150);
    });

    mutationObserver.observe(document.body,{
      childList:true,
      subtree:true,
      characterData:true
    });
  }

  function initialize(){
    bindLanguageSelectors();
    const saved=getSavedLanguage();
    currentLanguage=saved;
    setSelectorValue(saved);
    applyLanguage(saved,{silent:true}).finally(()=>{
      if(saved!==SOURCE_LANGUAGE){
        setTimeout(()=>translateNewContent(document.body),500);
        setTimeout(()=>translateNewContent(document.body),1500);
      }
    });
  }

  window.CSPTranslate={
    applyLanguage,
    getLanguage:()=>currentLanguage,
    getSavedLanguage,
    restoreSlovak:()=>applyLanguage(SOURCE_LANGUAGE),
    refresh:(root=document.body)=>translateNewContent(root),
    clearCache(){try{localStorage.removeItem(CACHE_STORAGE_KEY);}catch{}}
  };

  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',initialize,{once:true});
  else initialize();
})();
