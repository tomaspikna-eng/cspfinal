/*!
 * csp-auth.js — shared Supabase Auth helper for Connect Sports Pro
 *
 * Talks to the `csp-staging` Supabase project (the one built by the
 * migrations under /supabase/migrations — profiles, plan-gating,
 * tournaments, etc). This is a NEW project, separate from the
 * `gilzomwhuwcxpkegtlhj` / `gqtbxjkuemggelepkhrl` Supabase projects that
 * some older pages in this repo (nastavenie-profilu/, upgrade/, the
 * magazine read on the landing page) still point at — those were not
 * touched by this change. See the summary of this task for details.
 *
 * No build step, matching the rest of this repo: loads on top of the
 * UMD/CDN build of @supabase/supabase-js, the same pattern already used
 * for the QR code library in manager/stanice/index.html.
 *
 * Usage — include AFTER the supabase-js CDN script tag:
 *   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
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
  var SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxjbW95a2FxdnZmeWJ0b2JodHFnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMxNjc0ODUsImV4cCI6MjA5ODc0MzQ4NX0.l4-t_EgXOQh_3PjfracM-ECvrky58CP44LGwBgI9TDA';

  if (!global.supabase || typeof global.supabase.createClient !== 'function') {
    console.error('[csp-auth] @supabase/supabase-js was not found on window.supabase — make sure the CDN script tag is included BEFORE csp-auth.js.');
    return;
  }

  var client = global.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

  /** Wraps supabase.auth.signUp(). A `profiles` row is auto-created by the
   * existing on_auth_user_created DB trigger (migration 0001) — nothing
   * else to do here. Whether `data.session` comes back populated depends
   * on the project's email-confirmation setting (currently ON, i.e.
   * autoconfirm is OFF — see summary): if confirmation is required,
   * `data.session` will be null until the user clicks the emailed link. */
  function signUp(email, password) {
    return client.auth.signUp({ email: email, password: password });
  }

  /** Wraps supabase.auth.signInWithPassword(). */
  function signIn(email, password) {
    return client.auth.signInWithPassword({ email: email, password: password });
  }

  /** Wraps supabase.auth.signInWithOAuth({ provider: 'google' }).
   * NOTE: Google OAuth is NOT currently enabled on the csp-staging
   * Supabase project (Authentication > Providers > Google is off as of
   * this writing — confirmed via the project's /auth/v1/settings
   * endpoint). Kept here only for UI parity with the existing "Continue
   * with Google" button; calling this will return an error until a
   * Google OAuth client is configured in the Supabase dashboard. */
  function signInWithGoogle(redirectTo) {
    return client.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: redirectTo || (global.location.origin + '/profil/') }
    });
  }

  /** Wraps supabase.auth.signOut(). */
  function signOut() {
    return client.auth.signOut();
  }

  /** Wraps supabase.auth.getSession() — use on page load to check whether
   * someone is already logged in. */
  function getSession() {
    return client.auth.getSession();
  }

  /** After confirming a session exists, fetches that user's own row from
   * `profiles` (id, role, plan, is_admin, ...) via a normal select — this
   * is allowed by existing RLS (any authenticated user can read any
   * profile, including their own). Returns { data: null, error: null } if
   * there is no active session, in the same { data, error } shape
   * supabase-js itself uses. */
  async function getCurrentProfile() {
    var sessionResult = await client.auth.getSession();
    var session = sessionResult.data && sessionResult.data.session;
    if (!session) {
      return { data: null, error: null };
    }
    return client
      .from('profiles')
      .select('id, full_name, email, role, plan, is_admin, avatar_url')
      .eq('id', session.user.id)
      .single();
  }

  /** Turns a Supabase Auth error into a short, plain-language Slovak
   * message. Supabase's own error messages are already descriptive
   * (in English); this just translates the common cases so the UI reads
   * naturally, and falls back to the raw message for anything else
   * rather than a generic "something went wrong". */
  function friendlyError(error) {
    if (!error || !error.message) return 'Nastala neočakávaná chyba. Skús to znova.';
    var msg = error.message;
    var lower = msg.toLowerCase();
    if (lower.indexOf('invalid login credentials') !== -1) return 'Nesprávny e-mail alebo heslo.';
    if (lower.indexOf('email not confirmed') !== -1) return 'E-mail nie je potvrdený. Skontroluj svoju schránku.';
    if (lower.indexOf('already registered') !== -1 || lower.indexOf('already exists') !== -1 || lower.indexOf('user already registered') !== -1) return 'Tento e-mail je už registrovaný.';
    if (lower.indexOf('rate limit') !== -1) return 'Príliš veľa pokusov. Skús to o chvíľu znova.';
    if (lower.indexOf('password') !== -1 && lower.indexOf('least') !== -1) return msg; // Supabase's own "at least N characters" message is already clear
    return msg;
  }

  /** Supabase Auth does NOT return an error when signUp() is called with
   * an email that's already registered — this is deliberate
   * anti-enumeration behavior (confirmed live against this project: a
   * duplicate signup responds 200 with an empty `identities` array
   * instead of an error, indistinguishable from a genuine new signup by
   * error alone). Pass the `data` object from signUp()'s result to this
   * helper to detect that case and show an accurate message instead of a
   * misleading "check your email" success message. */
  function isDuplicateSignup(data) {
    return !!(data && data.user && Array.isArray(data.user.identities) && data.user.identities.length === 0);
  }

  global.cspAuth = {
    // Raw client, exposed for one-off queries this helper doesn't wrap
    // (e.g. reading/writing other tables once a session exists).
    client: client,
    signUp: signUp,
    signIn: signIn,
    signInWithGoogle: signInWithGoogle,
    signOut: signOut,
    getSession: getSession,
    getCurrentProfile: getCurrentProfile,
    friendlyError: friendlyError,
    isDuplicateSignup: isDuplicateSignup
  };
})(window);
