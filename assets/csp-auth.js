/*!
 * csp-auth.js — shared Supabase Auth helper for Connect Sports Pro
 *
 * Public Supabase publishable/anon keys are intentionally embedded in the
 * browser. Authorization is enforced by RLS, function ACLs and capability
 * tokens. Private profile fields are never read through the public profiles
 * relation; getCurrentProfile() uses get_my_profile_private().
 */
(function (global) {
  'use strict';

  var SUPABASE_URL = 'https://lcmoykaqvvfybtobhtqg.supabase.co';
  var SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxjbW95a2FxdnZmeWJ0b2JodHFnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMxNjc0ODUsImV4cCI6MjA5ODc0MzQ4NX0.l4-t_EgXOQh_3PjfracM-ECvrky58CP44LGwBgI9TDA';
  var PUBLIC_PROFILE_COLUMNS = 'id,full_name,role,plan,avatar_url,created_at,cover_url,bio,avatar_position_x,avatar_position_y,avatar_zoom';

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

  /*
   * Compatibility guard for legacy pages that use .from('profiles').select()
   * without an explicit column list. The database now grants browser clients
   * only public-safe profile columns, so wildcard RETURNING/SELECT must not
   * accidentally request email/is_admin/billing metadata.
   */
  (function protectProfileQueries() {
    var rawFrom = client.from.bind(client);
    client.from = function (relation) {
      var builder = rawFrom(relation);
      if (relation !== 'profiles' || !builder) return builder;

      if (typeof builder.select === 'function') {
        var rawSelect = builder.select.bind(builder);
        builder.select = function (columns, options) {
          var requested = !columns || String(columns).trim() === '*' ? PUBLIC_PROFILE_COLUMNS : columns;
          return rawSelect(requested, options);
        };
      }

      if (typeof builder.update === 'function') {
        var rawUpdate = builder.update.bind(builder);
        builder.update = function (values, options) {
          var filter = rawUpdate(values, options);
          if (filter && typeof filter.select === 'function') {
            var rawReturningSelect = filter.select.bind(filter);
            filter.select = function (columns) {
              var requested = !columns || String(columns).trim() === '*' ? PUBLIC_PROFILE_COLUMNS : columns;
              return rawReturningSelect(requested);
            };
          }
          return filter;
        };
      }

      if (typeof builder.insert === 'function') {
        var rawInsert = builder.insert.bind(builder);
        builder.insert = function (values, options) {
          var filter = rawInsert(values, options);
          if (filter && typeof filter.select === 'function') {
            var rawInsertSelect = filter.select.bind(filter);
            filter.select = function (columns) {
              var requested = !columns || String(columns).trim() === '*' ? PUBLIC_PROFILE_COLUMNS : columns;
              return rawInsertSelect(requested);
            };
          }
          return filter;
        };
      }

      return builder;
    };
  })();

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
    var user;
    if (knownUser && knownUser.id) {
      user = knownUser;
    } else {
      var sessionResult = await client.auth.getSession();
      var session = sessionResult.data && sessionResult.data.session;
      if (!session) return { data: null, error: null };
      user = session.user;
    }

    /*
     * Preferred path after the 2026-09-16 hardening migration. It returns
     * private data only for auth.uid(). A short fallback keeps deployments
     * backwards-compatible while the DB migration and static release cross.
     */
    var privateResult = await client.rpc('get_my_profile_private');
    if (!privateResult.error) {
      var privateRow = Array.isArray(privateResult.data) ? (privateResult.data[0] || null) : privateResult.data;
      if (privateRow && !privateRow.email && user && user.email) privateRow.email = user.email;
      return { data: privateRow, error: null };
    }

    var code = String(privateResult.error.code || '');
    var message = String(privateResult.error.message || '').toLowerCase();
    var migrationMissing = code === 'PGRST202' || message.indexOf('get_my_profile_private') !== -1;
    if (!migrationMissing) return privateResult;

    var legacyResult = await rawOwnProfileLookup(user.id);
    if (legacyResult.data && !legacyResult.data.email && user.email) legacyResult.data.email = user.email;
    return legacyResult;
  }

  function rawOwnProfileLookup(userId) {
    /* Use the original PostgREST relation through client.from(). The explicit
       list is required because wildcard profile reads are deliberately blocked. */
    return client
      .from('profiles')
      .select('id,full_name,role,plan,avatar_url,created_at,cover_url,bio,avatar_position_x,avatar_position_y,avatar_zoom')
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
    var dartsFormatScript = global.document.createElement('script');
    dartsFormatScript.src = '/assets/csp-darts-format.js?v=20260915-2';
    dartsFormatScript.defer = true;
    global.document.head.appendChild(dartsFormatScript);

    var dartsAchievementScript = global.document.createElement('script');
    dartsAchievementScript.src = '/assets/csp-darts-achievements.js?v=20260915-1';
    dartsAchievementScript.defer = true;
    global.document.head.appendChild(dartsAchievementScript);
  }

  if (global.Capacitor && global.Capacitor.isNativePlatform && global.Capacitor.isNativePlatform()) {
    var nativePushScript = global.document.createElement('script');
    nativePushScript.src = '/assets/csp-native-push.js?v=20260914-1';
    nativePushScript.defer = true;
    global.document.head.appendChild(nativePushScript);
  }
})(window);
