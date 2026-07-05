/*!
 * csp-manager.js — shared Club Manager auth/access helper
 *
 * Used by manager/Dashboard obsluhy/, manager/rezervacie/, and
 * manager/stanice/ so the same session + club_manager feature-gate +
 * current-club lookup logic isn't duplicated three times. Builds on top
 * of assets/csp-auth.js (must be loaded first) rather than creating a
 * second Supabase client.
 *
 * Usage — include AFTER csp-auth.js:
 *   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
 *   <script src="/assets/csp-auth.js"></script>
 *   <script src="/assets/csp-manager.js"></script>
 *
 * Exposes a single global: window.cspManager
 */
(function (global) {
  'use strict';

  if (!global.cspAuth) {
    console.error('[csp-manager] cspAuth was not found on window — make sure csp-auth.js is included BEFORE csp-manager.js.');
    return;
  }

  /** Checks session + the club_manager feature gate (has_feature_access(),
   * migration 0002, currently ultra-tier), and looks up the caller's own
   * club (a profile may not have created one yet — nothing does this
   * automatically). Redirects and returns null itself on any failure
   * case, so callers can just do:
   *
   *   const ctx = await cspManager.requireClubManagerAccess();
   *   if (!ctx) return; // already redirected
   *
   * Pass { allowNoClub: true } for pages that handle a missing club
   * themselves (e.g. showing a "create your club" flow) instead of being
   * redirected to the Dashboard for it. */
  async function requireClubManagerAccess(opts) {
    opts = opts || {};
    try {
      const { data: { session } } = await cspAuth.withTimeout(cspAuth.getSession(), 8000, 'getSession()');
      if (!session) {
        global.location.href = '/login/';
        return null;
      }

      const { data: hasAccess, error: accessError } = await cspAuth.withTimeout(
        cspAuth.client.rpc('has_feature_access', { uid: session.user.id, key: 'club_manager' }),
        8000,
        'has_feature_access()'
      );
      if (accessError) {
        console.error('[csp-manager] has_feature_access check failed:', accessError);
      }
      if (!hasAccess) {
        global.location.href = '/upgrade/';
        return null;
      }

      const { data: profile, error: profileError } = await cspAuth.withTimeout(
        cspAuth.getCurrentProfile(session.user),
        8000,
        'getCurrentProfile()'
      );
      if (profileError) {
        console.error('[csp-manager] Could not load profile:', profileError);
      }

      const { data: club, error: clubError } = await cspAuth.withTimeout(
        cspAuth.client.from('clubs').select('id, name').eq('owner_id', session.user.id).maybeSingle(),
        8000,
        'clubs lookup'
      );
      if (clubError) {
        console.error('[csp-manager] Could not load club:', clubError);
      }

      if (!club && !opts.allowNoClub) {
        global.location.href = '/manager/Dashboard%20obsluhy/';
        return null;
      }

      return { session: session, profile: profile || null, club: club || null };
    } catch (err) {
      console.error('[csp-manager] Auth/access check failed or timed out:', err);
      global.location.href = '/login/';
      return null;
    }
  }

  /** Real sign-out, replacing the old alert() stub. */
  async function signOut() {
    try {
      await cspAuth.withTimeout(cspAuth.signOut(), 8000, 'signOut()');
    } catch (err) {
      console.error('[csp-manager] signOut failed or timed out, redirecting to /login/ anyway:', err);
    }
    global.location.href = '/login/';
  }

  global.cspManager = {
    requireClubManagerAccess: requireClubManagerAccess,
    signOut: signOut
  };
})(window);
