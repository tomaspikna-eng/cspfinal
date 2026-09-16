/* CSP registration anti-bot helper.
 * This is a lightweight human-interaction check, not provider-backed CAPTCHA.
 */
(function (global) {
  'use strict';

  var openedAt = Date.now();
  var MIN_HUMAN_TIME_MS = 3000;

  function validate() {
    var checkbox = global.document.getElementById('humanCheck');
    var honeypot = global.document.getElementById('website');

    if (honeypot && honeypot.value.trim()) {
      return { ok: false, message: 'Registráciu sa nepodarilo overiť. Skús to znova.' };
    }

    if (!checkbox || !checkbox.checked) {
      return { ok: false, message: 'Potvrď prosím, že nie si robot.' };
    }

    if (Date.now() - openedAt < MIN_HUMAN_TIME_MS) {
      if (checkbox) checkbox.checked = false;
      return { ok: false, message: 'Formulár bol odoslaný príliš rýchlo. Skús to ešte raz.' };
    }

    return { ok: true };
  }

  global.cspRegistrationHumanCheck = { validate: validate };
})(window);
