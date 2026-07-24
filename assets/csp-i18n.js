(() => {
  'use strict';

  const SELECTOR = '.lang-select';
  const STORAGE_KEY = 'csp_language';
  const SOURCE_LANG = 'sk';

  const API_LANG = {
    SK: 'sk',
    CZ: 'cs',
    EN: 'en',
    DE: 'de',
    PL: 'pl',
  };

  const originalText = new WeakMap();
  const originalAttr = new WeakMap();
  let currentLang = 'SK';
  let applying = false;
  let observerTimer = null;

  function shouldSkipElement(el) {
    if (!el) return true;
    return !!el.closest(
      'script,style,noscript,code,pre,svg,canvas,' +
      '[data-no-translate],.landing-tournament-name'
    );
  }

  function normalizeText(value) {
    return String(value || '').replace(/\s+/g, ' ').trim();
  }

  function getTextNodes(root = document.body) {
    const out = [];
    const walker = document.createTreeWalker(
      root,
      NodeFilter.SHOW_TEXT,
      {
        acceptNode(node) {
          const text = normalizeText(node.nodeValue);
          if (!text) return NodeFilter.FILTER_REJECT;
          if (!node.parentElement || shouldSkipElement(node.parentElement)) {
            return NodeFilter.FILTER_REJECT;
          }
          if (/^[\d\s.,:;/%+–—→←€$#()\-]+$/.test(text)) {
            return NodeFilter.FILTER_REJECT;
          }
          return NodeFilter.FILTER_ACCEPT;
        },
      }
    );

    let node;
    while ((node = walker.nextNode())) {
      if (!originalText.has(node)) {
        originalText.set(node, node.nodeValue);
      }
      out.push(node);
    }
    return out;
  }

  function getAttributeTargets(root = document.body) {
    const attrs = ['placeholder', 'title', 'aria-label'];
    const rows = [];

    root.querySelectorAll('*').forEach(el => {
      if (shouldSkipElement(el)) return;

      attrs.forEach(attr => {
        if (!el.hasAttribute(attr)) return;
        const value = normalizeText(el.getAttribute(attr));
        if (!value) return;

        let map = originalAttr.get(el);
        if (!map) {
          map = {};
          originalAttr.set(el, map);
        }
        if (!(attr in map)) map[attr] = el.getAttribute(attr);

        rows.push({ el, attr, original: map[attr] });
      });
    });

    return rows;
  }

  async function translateBatch(texts, target) {
    const response = await fetch('/api/translate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        texts,
        source: SOURCE_LANG,
        target,
      }),
    });

    const body = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(body.error || `Translation API ${response.status}`);
    }

    if (!Array.isArray(body.translations) ||
        body.translations.length !== texts.length) {
      throw new Error('Invalid translation response');
    }

    return body.translations;
  }

  async function translateItems(items, target, applyFn) {
    const chunkSize = 80;

    for (let start = 0; start < items.length; start += chunkSize) {
      const chunk = items.slice(start, start + chunkSize);
      const sourceTexts = chunk.map(item => normalizeText(item.original));
      const translated = await translateBatch(sourceTexts, target);

      chunk.forEach((item, index) => {
        applyFn(item, translated[index]);
      });
    }
  }

  function restoreSlovak() {
    applying = true;

    getTextNodes().forEach(node => {
      node.nodeValue = originalText.get(node);
    });

    getAttributeTargets().forEach(item => {
      item.el.setAttribute(item.attr, item.original);
    });

    document.documentElement.lang = 'sk';
    applying = false;
  }

  async function applyLanguage(langCode) {
    const normalized = String(langCode || 'SK').toUpperCase();
    if (!API_LANG[normalized]) return;

    currentLang = normalized;
    localStorage.setItem(STORAGE_KEY, normalized);

    const select = document.querySelector(SELECTOR);
    if (select && select.value !== normalized) select.value = normalized;

    restoreSlovak();

    if (normalized === 'SK') return;

    const target = API_LANG[normalized];
    const textNodes = getTextNodes().map(node => ({
      node,
      original: originalText.get(node),
    }));
    const attrs = getAttributeTargets();

    applying = true;

    try {
      await translateItems(textNodes, target, (item, translated) => {
        const original = item.original;
        const leading = original.match(/^\s*/)?.[0] || '';
        const trailing = original.match(/\s*$/)?.[0] || '';
        item.node.nodeValue = `${leading}${translated}${trailing}`;
      });

      await translateItems(attrs, target, (item, translated) => {
        item.el.setAttribute(item.attr, translated);
      });

      document.documentElement.lang = target;
    } catch (error) {
      console.error('[CSP i18n]', error);
      restoreSlovak();
    } finally {
      applying = false;
    }
  }

  function scheduleDynamicRefresh() {
    if (applying || currentLang === 'SK') return;
    clearTimeout(observerTimer);
    observerTimer = setTimeout(() => applyLanguage(currentLang), 250);
  }

  function init() {
    const select = document.querySelector(SELECTOR);
    if (!select) return;

    getTextNodes();
    getAttributeTargets();

    select.addEventListener('change', event => {
      applyLanguage(event.target.value);
    });

    const saved = (localStorage.getItem(STORAGE_KEY) || 'SK').toUpperCase();
    if (API_LANG[saved]) {
      select.value = saved;
      applyLanguage(saved);
    }

    const observer = new MutationObserver(scheduleDynamicRefresh);
    observer.observe(document.body, {
      childList: true,
      subtree: true,
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init, { once: true });
  } else {
    init();
  }
})();
