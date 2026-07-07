/*!
 * cookie-consent.js — shared cookie consent banner for Connect Sports Pro
 *
 * Include on any page with: <script src="/assets/cookie-consent.js"></script>
 * Shows a bottom banner on first visit, remembers the choice in
 * localStorage (key: csp_cookie_consent_v1) so it never shows again once
 * accepted. Only covers essential + functional cookies (see /cookies/) —
 * no third-party ad/analytics consent to manage, since none are used.
 */
(function(){
  var CONSENT_KEY = 'csp_cookie_consent_v1';

  function alreadyConsented(){
    try{ return localStorage.getItem(CONSENT_KEY) === 'accepted'; }
    catch(e){ return false; } // if localStorage is blocked, don't nag on every load
  }

  function setConsent(){
    try{ localStorage.setItem(CONSENT_KEY, 'accepted'); }catch(e){}
  }

  function injectBanner(){
    var el = document.createElement('div');
    el.id = 'cspCookieBanner';
    el.innerHTML =
      '<style>' +
      '#cspCookieBanner{position:fixed;left:0;right:0;bottom:0;z-index:9999;' +
      'background:#0c0c0f;border-top:1px solid rgba(255,255,255,.1);' +
      'padding:16px 20px;display:flex;flex-wrap:wrap;gap:14px;align-items:center;' +
      'justify-content:space-between;font-family:"Segoe UI",system-ui,sans-serif;' +
      'box-shadow:0 -8px 24px rgba(0,0,0,.35)}' +
      '#cspCookieBanner p{margin:0;color:#d0d0d6;font-size:.86rem;line-height:1.5;max-width:640px}' +
      '#cspCookieBanner a{color:#d4a843;text-decoration:none}' +
      '#cspCookieBanner a:hover{text-decoration:underline}' +
      '#cspCookieBanner .cspCookieBtn{flex-shrink:0;font-family:inherit;font-weight:700;' +
      'font-size:.86rem;padding:10px 20px;border-radius:9px;border:none;cursor:pointer;' +
      'background:#d4a843;color:#1a1000}' +
      '#cspCookieBanner .cspCookieBtn:hover{background:#e8b94f}' +
      '@media(max-width:520px){#cspCookieBanner{flex-direction:column;align-items:stretch;text-align:center}' +
      '#cspCookieBanner .cspCookieBtn{width:100%}}' +
      '</style>' +
      '<p>Používame nevyhnutné a funkčné cookies, aby appka fungovala správne (napr. prihlásenie). Žiadne reklamné ani sledovacie cookies tretích strán nepoužívame. <a href="/cookies/">Viac informácií</a></p>' +
      '<button class="cspCookieBtn" type="button">Rozumiem</button>';

    document.body.appendChild(el);
    el.querySelector('.cspCookieBtn').addEventListener('click', function(){
      setConsent();
      el.remove();
    });
  }

  function init(){
    if(alreadyConsented()) return;
    if(document.body) injectBanner();
    else document.addEventListener('DOMContentLoaded', injectBanner);
  }

  init();
})();
