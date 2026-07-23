(() => {
  'use strict';

  const STORAGE_KEY = 'csp_cookie_consent_v1';
  const CONSENT_VERSION = 1;

  const DEFAULT = {
    version: CONSENT_VERSION,
    necessary: true,
    analytics: false,
    marketing: false,
    updatedAt: null
  };

  const css = `
  #csp-cookie-banner,#csp-cookie-settings{font-family:Inter,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
  #csp-cookie-banner * ,#csp-cookie-settings *{box-sizing:border-box}
  #csp-cookie-banner{
    position:fixed;left:18px;right:18px;bottom:18px;z-index:99999;
    max-width:1180px;margin:0 auto;background:#111116;color:#f4f4f4;
    border:1px solid rgba(255,255,255,.10);border-radius:18px;
    box-shadow:0 24px 80px rgba(0,0,0,.55);padding:20px;
  }
  #csp-cookie-banner.csp-hidden,#csp-cookie-settings.csp-hidden{display:none!important}
  .csp-cookie-grid{display:grid;grid-template-columns:1fr auto;gap:22px;align-items:center}
  .csp-cookie-title{font-size:1.05rem;font-weight:800;margin:0 0 7px}
  .csp-cookie-title .gold{color:#d8b04b}
  .csp-cookie-text{margin:0;color:#aaaab3;font-size:.88rem;line-height:1.55;max-width:760px}
  .csp-cookie-text a{color:#d8b04b;text-decoration:none}.csp-cookie-text a:hover{text-decoration:underline}
  .csp-cookie-actions{display:flex;gap:9px;flex-wrap:wrap;justify-content:flex-end}
  .csp-cookie-btn{
    appearance:none;border:1px solid rgba(255,255,255,.12);border-radius:10px;
    padding:11px 15px;background:#19191f;color:#f4f4f4;font-weight:750;
    font-size:.82rem;cursor:pointer;white-space:nowrap
  }
  .csp-cookie-btn:hover{border-color:#d8b04b}
  .csp-cookie-btn.primary{background:#22d36b;border-color:#22d36b;color:#07180c}
  .csp-cookie-btn.reject{background:transparent}
  .csp-cookie-btn.gold{background:#d8b04b;border-color:#d8b04b;color:#1b1404}
  #csp-cookie-settings{
    position:fixed;inset:0;z-index:100000;background:rgba(0,0,0,.78);
    display:flex;align-items:center;justify-content:center;padding:18px
  }
  .csp-cookie-modal{
    width:min(620px,100%);max-height:min(760px,92vh);overflow:auto;
    background:#111116;color:#f4f4f4;border:1px solid rgba(255,255,255,.10);
    border-radius:20px;padding:22px;box-shadow:0 30px 100px rgba(0,0,0,.65)
  }
  .csp-cookie-modal-head{display:flex;justify-content:space-between;gap:16px;align-items:flex-start}
  .csp-cookie-modal h2{margin:0;font-size:1.35rem}
  .csp-cookie-close{background:none;border:0;color:#aaaab3;font-size:1.4rem;cursor:pointer}
  .csp-cookie-intro{color:#aaaab3;font-size:.86rem;line-height:1.55;margin:10px 0 18px}
  .csp-cookie-category{
    border:1px solid rgba(255,255,255,.08);border-radius:13px;padding:15px;
    margin-top:10px;background:#16161c
  }
  .csp-cookie-cat-top{display:flex;justify-content:space-between;gap:14px;align-items:center}
  .csp-cookie-cat-name{font-weight:800;font-size:.92rem}
  .csp-cookie-cat-desc{color:#92929c;font-size:.78rem;line-height:1.5;margin-top:5px;padding-right:45px}
  .csp-cookie-always{color:#22d36b;font-size:.72rem;font-weight:800}
  .csp-switch{position:relative;width:46px;height:26px;flex:0 0 46px}
  .csp-switch input{opacity:0;width:0;height:0}
  .csp-slider{position:absolute;cursor:pointer;inset:0;background:#34343c;border-radius:99px;transition:.18s}
  .csp-slider:before{content:"";position:absolute;width:20px;height:20px;left:3px;top:3px;background:#fff;border-radius:50%;transition:.18s}
  .csp-switch input:checked + .csp-slider{background:#22d36b}
  .csp-switch input:checked + .csp-slider:before{transform:translateX(20px)}
  .csp-cookie-modal-actions{display:flex;gap:9px;justify-content:flex-end;flex-wrap:wrap;margin-top:18px}
  #csp-cookie-reopen{
    position:fixed;left:14px;bottom:14px;z-index:99990;
    border:1px solid rgba(255,255,255,.12);border-radius:999px;background:#111116;
    color:#c7c7ce;padding:8px 12px;font:700 .72rem Inter,system-ui,sans-serif;
    cursor:pointer;box-shadow:0 8px 30px rgba(0,0,0,.35)
  }
  #csp-cookie-reopen:hover{border-color:#d8b04b;color:#d8b04b}
  @media(max-width:760px){
    #csp-cookie-banner{left:10px;right:10px;bottom:10px;padding:16px}
    .csp-cookie-grid{grid-template-columns:1fr}
    .csp-cookie-actions{justify-content:stretch}
    .csp-cookie-actions .csp-cookie-btn{flex:1}
  }`;

  function injectStyles() {
    if (document.getElementById('csp-cookie-style')) return;
    const style = document.createElement('style');
    style.id = 'csp-cookie-style';
    style.textContent = css;
    document.head.appendChild(style);
  }

  function readConsent() {
    try {
      const parsed = JSON.parse(localStorage.getItem(STORAGE_KEY));
      if (!parsed || parsed.version !== CONSENT_VERSION) return null;
      return { ...DEFAULT, ...parsed, necessary: true };
    } catch {
      return null;
    }
  }

  function writeConsent(next) {
    const value = {
      ...DEFAULT,
      ...next,
      version: CONSENT_VERSION,
      necessary: true,
      updatedAt: new Date().toISOString()
    };
    localStorage.setItem(STORAGE_KEY, JSON.stringify(value));
    applyConsent(value);
    document.dispatchEvent(new CustomEvent('csp:cookie-consent', { detail: value }));
    return value;
  }

  function currentConsent() {
    return readConsent() || { ...DEFAULT };
  }

  function enableDeferredScripts(category) {
    document.querySelectorAll(
      `script[type="text/plain"][data-cookie-category="${category}"]:not([data-cookie-loaded="1"])`
    ).forEach(node => {
      const script = document.createElement('script');
      [...node.attributes].forEach(attr => {
        if (!['type', 'data-cookie-category', 'data-cookie-loaded'].includes(attr.name)) {
          script.setAttribute(attr.name, attr.value);
        }
      });
      if (node.src) script.src = node.src;
      else script.textContent = node.textContent;
      script.dataset.cookieLoaded = '1';
      node.dataset.cookieLoaded = '1';
      node.parentNode.insertBefore(script, node.nextSibling);
    });
  }

  function applyConsent(consent) {
    if (consent.analytics) enableDeferredScripts('analytics');
    if (consent.marketing) enableDeferredScripts('marketing');

    // Optional integrations can listen to this global state.
    window.CSPCookies.state = consent;
  }

  function bannerHtml() {
    return `
      <div id="csp-cookie-banner" class="csp-hidden" role="dialog" aria-modal="false" aria-labelledby="csp-cookie-title">
        <div class="csp-cookie-grid">
          <div>
            <h2 class="csp-cookie-title" id="csp-cookie-title"><span class="gold">Connect Sports Pro</span> používa cookies</h2>
            <p class="csp-cookie-text">
              Nevyhnutné cookies a lokálne úložisko používame na fungovanie webu a uloženie tvojich nastavení.
              Analytické a marketingové technológie použijeme iba po tvojom súhlase.
              Nastavenie môžeš kedykoľvek zmeniť.
              <a href="/cookies/">Viac informácií</a>
            </p>
          </div>
          <div class="csp-cookie-actions">
            <button class="csp-cookie-btn reject" data-cookie-action="reject">Odmietnuť nepovinné</button>
            <button class="csp-cookie-btn" data-cookie-action="settings">Nastavenia</button>
            <button class="csp-cookie-btn primary" data-cookie-action="accept">Prijať všetko</button>
          </div>
        </div>
      </div>`;
  }

  function settingsHtml() {
    return `
      <div id="csp-cookie-settings" class="csp-hidden" role="dialog" aria-modal="true" aria-labelledby="csp-cookie-settings-title">
        <div class="csp-cookie-modal">
          <div class="csp-cookie-modal-head">
            <div>
              <h2 id="csp-cookie-settings-title">Nastavenia cookies</h2>
              <div class="csp-cookie-intro">Vyber, ktoré nepovinné technológie môže Connect Sports Pro používať. Nevyhnutné funkcie sa nedajú vypnúť.</div>
            </div>
            <button class="csp-cookie-close" data-cookie-action="close-settings" aria-label="Zavrieť">×</button>
          </div>

          <div class="csp-cookie-category">
            <div class="csp-cookie-cat-top">
              <div>
                <div class="csp-cookie-cat-name">Nevyhnutné</div>
                <div class="csp-cookie-cat-desc">Prihlásenie, bezpečnosť, základná funkčnosť webu a uloženie tvojej voľby cookies.</div>
              </div>
              <span class="csp-cookie-always">VŽDY AKTÍVNE</span>
            </div>
          </div>

          <div class="csp-cookie-category">
            <div class="csp-cookie-cat-top">
              <div>
                <div class="csp-cookie-cat-name">Analytické</div>
                <div class="csp-cookie-cat-desc">Pomáhajú merať návštevnosť a používanie webu, aby sme vedeli CSP zlepšovať.</div>
              </div>
              <label class="csp-switch">
                <input type="checkbox" id="csp-cookie-analytics">
                <span class="csp-slider"></span>
              </label>
            </div>
          </div>

          <div class="csp-cookie-category">
            <div class="csp-cookie-cat-top">
              <div>
                <div class="csp-cookie-cat-name">Marketingové</div>
                <div class="csp-cookie-cat-desc">Používajú sa na meranie kampaní, remarketing a obsah tretích strán.</div>
              </div>
              <label class="csp-switch">
                <input type="checkbox" id="csp-cookie-marketing">
                <span class="csp-slider"></span>
              </label>
            </div>
          </div>

          <div class="csp-cookie-modal-actions">
            <button class="csp-cookie-btn reject" data-cookie-action="reject">Odmietnuť nepovinné</button>
            <button class="csp-cookie-btn gold" data-cookie-action="save-settings">Uložiť nastavenia</button>
            <button class="csp-cookie-btn primary" data-cookie-action="accept">Prijať všetko</button>
          </div>
        </div>
      </div>`;
  }

  function reopenHtml() {
    return `<button id="csp-cookie-reopen" class="csp-hidden" type="button">Nastavenia cookies</button>`;
  }

  function showBanner() {
    document.getElementById('csp-cookie-banner')?.classList.remove('csp-hidden');
    document.getElementById('csp-cookie-reopen')?.classList.add('csp-hidden');
  }

  function hideBanner() {
    document.getElementById('csp-cookie-banner')?.classList.add('csp-hidden');
    document.getElementById('csp-cookie-reopen')?.classList.remove('csp-hidden');
  }

  function openSettings() {
    const state = currentConsent();
    document.getElementById('csp-cookie-analytics').checked = !!state.analytics;
    document.getElementById('csp-cookie-marketing').checked = !!state.marketing;
    document.getElementById('csp-cookie-settings')?.classList.remove('csp-hidden');
  }

  function closeSettings() {
    document.getElementById('csp-cookie-settings')?.classList.add('csp-hidden');
  }

  function acceptAll() {
    writeConsent({ analytics: true, marketing: true });
    hideBanner();
    closeSettings();
  }

  function rejectOptional() {
    writeConsent({ analytics: false, marketing: false });
    hideBanner();
    closeSettings();
  }

  function saveSettings() {
    writeConsent({
      analytics: !!document.getElementById('csp-cookie-analytics')?.checked,
      marketing: !!document.getElementById('csp-cookie-marketing')?.checked
    });
    hideBanner();
    closeSettings();
  }

  function bindEvents() {
    document.addEventListener('click', event => {
      const action = event.target.closest('[data-cookie-action]')?.dataset.cookieAction;
      if (!action) return;
      if (action === 'accept') acceptAll();
      if (action === 'reject') rejectOptional();
      if (action === 'settings') openSettings();
      if (action === 'close-settings') closeSettings();
      if (action === 'save-settings') saveSettings();
    });

    document.getElementById('csp-cookie-reopen')?.addEventListener('click', openSettings);

    document.addEventListener('keydown', event => {
      if (event.key === 'Escape') closeSettings();
    });
  }

  function init() {
    injectStyles();
    document.body.insertAdjacentHTML('beforeend', bannerHtml() + settingsHtml() + reopenHtml());
    bindEvents();

    const saved = readConsent();
    if (saved) {
      applyConsent(saved);
      document.getElementById('csp-cookie-reopen')?.classList.remove('csp-hidden');
    } else {
      showBanner();
    }
  }

  window.CSPCookies = {
    state: { ...DEFAULT },
    get: currentConsent,
    can(category) {
      if (category === 'necessary') return true;
      return !!currentConsent()[category];
    },
    openSettings,
    reset() {
      localStorage.removeItem(STORAGE_KEY);
      location.reload();
    }
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init, { once: true });
  } else {
    init();
  }
})();