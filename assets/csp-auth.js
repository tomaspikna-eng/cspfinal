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
  var SAFE_MATCH_COLUMNS = [
    'id','tournament_id','round_key','player1_id','player2_id','score1','score2','winner_id','status',
    'created_at','updated_at','player1_reported_score','player1_reported_at','player2_reported_score',
    'player2_reported_at','phase_id','round_number','match_number','bracket_side','next_match_id',
    'loser_next_match_id','player1_source','player2_source','station_id','scheduled_at','called_at',
    'arrival_deadline_at','penalty_1_at','penalty_2_at','penalty_3_at','forfeit_at','late_player_id',
    'penalty_score_awarded','forfeit_reason','match_call_status','player1_ready_at','player2_ready_at',
    'started_at','completed_at','shot_clock_enabled','shot_clock_seconds','post_break_seconds',
    'extension_seconds','extensions_allowed','extensions_used_player1','extensions_used_player2',
    'shot_clock_operator_id','shot_clock_started_at','shot_clock_paused_at','shot_clock_remaining_seconds',
    'shot_clock_current_player_id','match_clock_elapsed_seconds','match_clock_started_at',
    'match_clock_paused_at','match_clock_stopped_at','station_label','tournament_resource_id',
    'tournament_resource_label','result_source','result_submitted_at','player1_timeout_active',
    'player2_timeout_active','player1_timeout_at','player2_timeout_at','group_index','race_to','race_to_key'
  ].join(',');
  var SAFE_RESOURCE_COLUMNS = [
    'id','tournament_id','resource_number','label','resource_type','status','current_match_id','is_active',
    'sort_order','created_at','updated_at','tablet_paired_at','tablet_last_seen_at','tablet_name',
    'operating_mode','automation_enabled'
  ].join(',');
  var SAFE_RELATION_COLUMNS = {
    profiles: PUBLIC_PROFILE_COLUMNS,
    matches: SAFE_MATCH_COLUMNS,
    tournament_resources: SAFE_RESOURCE_COLUMNS
  };

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
   * Compatibility guard for legacy static pages using select('*') or a
   * mutation followed by .select(). Capability secrets are deliberately not
   * selectable after the security migration, so wildcard requests must be
   * expanded to the public-safe columns before PostgREST receives them.
   * Explicit column lists are never rewritten.
   */
  (function protectBrowserQueries() {
    var rawFrom = client.from.bind(client);

    function safeRequestedColumns(relation, columns) {
      var safe = SAFE_RELATION_COLUMNS[relation];
      if (!safe) return columns;
      return !columns || String(columns).trim() === '*' ? safe : columns;
    }

    function protectReturningSelect(filter, relation) {
      if (!filter || typeof filter.select !== 'function') return filter;
      var rawReturningSelect = filter.select.bind(filter);
      filter.select = function (columns) {
        return rawReturningSelect(safeRequestedColumns(relation, columns));
      };
      return filter;
    }

    client.from = function (relation) {
      var builder = rawFrom(relation);
      if (!builder || !SAFE_RELATION_COLUMNS[relation]) return builder;

      if (typeof builder.select === 'function') {
        var rawSelect = builder.select.bind(builder);
        builder.select = function (columns, options) {
          return rawSelect(safeRequestedColumns(relation, columns), options);
        };
      }

      ['update', 'insert', 'upsert'].forEach(function (methodName) {
        if (typeof builder[methodName] !== 'function') return;
        var rawMutation = builder[methodName].bind(builder);
        builder[methodName] = function () {
          var filter = rawMutation.apply(null, arguments);
          return protectReturningSelect(filter, relation);
        };
      });

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
    return client
      .from('profiles')
      .select(PUBLIC_PROFILE_COLUMNS)
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
