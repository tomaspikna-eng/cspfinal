/*!
 * csp-auth.js — shared Supabase Auth helper for Connect Sports Pro
 *
 * Talks to the `csp-staging` Supabase project (the one built by the
 * migrations under /supabase/migrations — profiles, plan-gating,
 * tournaments, etc). This is a NEW project; several older pages used to
 * point at other, unused Supabase projects with schemas that don't exist
 * here (`subscriptions`/`organizations`/`profiles.username`, none of
 * which are in csp-staging) — all of them have now been migrated onto
 * this shared client: login/, registracia/, profil/, the landing page's
 * magazine widget, and upgrade/ (which now reads profiles.plan/role
 * directly instead of the old subscriptions/organizations tables — plan
 * changes stay admin/manual for now, no billing integration exists).
 * A dead events-fetching script on the landing page (no backing UI at
 * all) was removed outright, since no events backend exists yet.
 * (nastavenie-profilu/ previously also pointed at an old project; that
 * page has since been removed — profil/ is now the single canonical
 * profile page.) The old project URLs/keys themselves are no longer
 * referenced anywhere in functional code, only in this historical note.
 *
 * No build step, matching the rest of this repo: loads on top of the
 * UMD/CDN build of @supabase/supabase-js, the same pattern already used
 * for the QR code library in manager/stanice/index.html.
 *
 * Usage — include AFTER the supabase-js CDN script tag:
 *   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.57.4/dist/umd/supabase.min.js"></script>
 *   <script src="/assets/csp-auth.js"></script>
 *
 * Exposes a single global: window.cspAuth
 */
(function (global) {
  'use strict';

  var SUPABASE_URL = 'https://lcmoykaqvvfybtobhtqg.supabase.co';
  // Anon/public key — safe to embed in frontend JS. Access control is
  // enforced entirely by RLS policies on the database (see
  // supabase/migrations/0001_auth_profiles.sql onward), not by keeping
  // this key secret.
  var SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJIUzI1NiIsInJlZiI6ImxjbW95a2FxdnZmeWJ0b2JodHFnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMxNjc0ODUsImV4cCI6MjA5ODc0MzQ4NX0.l4-t_EgXOQh_3PjfracM-ECvrky58CP44LGwBgI9TDA';

  if (!global.supabase || typeof global.supabase.createClient !== 'function') {
    console.error('[csp-auth] @supabase/supabase-js was not found on window.supabase — make sure the CDN script tag is included BEFORE csp-auth.js.');
    return;
  }

  var client = global.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: {
      persistSession: true,
      autoRefreshToken: true,
      detectSessionInUrl: true
    }
  });

  function signUp(email, password) {
    return client.auth.signUp({ email: email, password: password });
  }

  function signIn(email, password) {
    return client.auth.signInWithPassword({ email: email, password: password });
  }

  function signInWithGoogle(redirectTo) {
    return client.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: redirectTo || (global.location.origin + '/profil/') }
    });
  }

  function signOut() {
    return client.auth.signOut();
  }

  function getSession() {
    return client.auth.getSession();
  }

  async function getCurrentProfile(knownUser) {
    var userId;
    if (knownUser && knownUser.id) {
      userId = knownUser.id;
    } else {
      var sessionResult = await client.auth.getSession();
      var session = sessionResult.data && sessionResult.data.session;
      if (!session) {
        return { data: null, error: null };
      }
      userId = session.user.id;
    }
    return client
      .from('profiles')
      .select('id, full_name, email, role, plan, is_admin, avatar_url, created_at')
      .eq('id', userId)
      .single();
  }

  function friendlyError(error) {
    if (!error || !error.message) return 'Nastala neočakávaná chyba. Skús to znova.';
    var msg = error.message;
    var lower = msg.toLowerCase();
    if (lower.indexOf('invalid login credentials') !== -1) return 'Nesprávny e-mail alebo heslo.';
    if (lower.indexOf('email not confirmed') !== -1) return 'E-mail nie je potvrdený. Skontroluj svoju schránku.';
    if (lower.indexOf('already registered') !== -1 || lower.indexOf('already exists') !== -1 || lower.indexOf('user already registered') !== -1) return 'Tento e-mail je už registrovaný.';
    if (lower.indexOf('rate limit') !== -1) return 'Príliš veľa pokusov. Skús to o chvíľu znova.';
    if (lower.indexOf('password') !== -1 && lower.indexOf('least') !== -1) return msg;
    return msg;
  }

  function isDuplicateSignup(data) {
    return !!(data && data.user && Array.isArray(data.user.identities) && data.user.identities.length === 0);
  }

  function withTimeout(promise, ms, label) {
    return Promise.race([
      promise,
      new Promise(function (_, reject) {
        setTimeout(function () {
          reject(new Error((label || 'operation') + ' timed out after ' + ms + 'ms'));
        }, ms);
      })
    ]);
  }

  global.cspAuth = {
    client: client,
    signUp: signUp,
    signIn: signIn,
    signInWithGoogle: signInWithGoogle,
    signOut: signOut,
    getSession: getSession,
    getCurrentProfile: getCurrentProfile,
    friendlyError: friendlyError,
    isDuplicateSignup: isDuplicateSignup,
    withTimeout: withTimeout
  };

  // Realtime visual reward: on every authenticated CSP page using csp-auth,
  // listen for newly unlocked achievements and show the Premium Seal popup.
  var achievementScript = global.document.createElement('script');
  achievementScript.src = '/assets/csp-achievement-unlock.js?v=20260915-1';
  achievementScript.defer = true;
  achievementScript.onload = function () {
    if (global.cspAchievementUnlock) global.cspAchievementUnlock.bind(client);
  };
  global.document.head.appendChild(achievementScript);

  if (/^\/turnament\/?$/.test(global.location.pathname)) {
    var completedTournamentLayoutScript = global.document.createElement('script');
    completedTournamentLayoutScript.src = '/assets/csp-tournament-completed-layout.js?v=20260915-1';
    completedTournamentLayoutScript.defer = true;
    global.document.head.appendChild(completedTournamentLayoutScript);
  }

  if (/^\/scoreboard\/?$/.test(global.location.pathname)) {
    // Darts training format: custom Best of N legs. Example: Best of 3 ends
    // at 2:0 or 2:1; Best of 5 ends when a player reaches 3 legs.
    var dartsFormatScript = global.document.createElement('script');
    dartsFormatScript.src = '/assets/csp-darts-format.js?v=20260915-2';
    dartsFormatScript.defer = true;
    global.document.head.appendChild(dartsFormatScript);

    // Darts achievements: record only metrics that the current aggregate-score
    // scoreboard can determine reliably (180s, high checkouts and visit streaks).
    var dartsAchievementScript = global.document.createElement('script');
    dartsAchievementScript.src = '/assets/csp-darts-achievements.js?v=20260915-1';
    dartsAchievementScript.defer = true;
    global.document.head.appendChild(dartsAchievementScript);
  }

  // Capacitor Android only: attach native push registration/deep-link bridge.
  if (global.Capacitor && global.Capacitor.isNativePlatform && global.Capacitor.isNativePlatform()) {
    var nativePushScript = global.document.createElement('script');
    nativePushScript.src = '/assets/csp-native-push.js?v=20260914-1';
    nativePushScript.defer = true;
    global.document.head.appendChild(nativePushScript);
  }
})(window);
