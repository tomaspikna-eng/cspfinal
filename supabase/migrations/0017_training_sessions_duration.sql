-- ============================================================================
-- CSP Database — Migration 0017: Add Match Duration to Training Sessions
-- ============================================================================
-- Numbering: checked `supabase migration list` against csp-staging first —
-- the highest CLI-tracked migration is 0016 (training_sessions), so this
-- is 0017. (0011-0014 remain reserved/applied outside git, per 0016's own
-- numbering note.)
--
-- training_sessions (migration 0016) doesn't currently capture how long a
-- match took. A stopwatch is being added to the scoreboard UI (separate
-- frontend task, right after this) that needs somewhere to save its
-- result.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. training_sessions.duration_seconds
-- ----------------------------------------------------------------------------
-- Nullable, no default: a session saved before this feature existed, or
-- one where the stopwatch data is unavailable for any reason, simply has
-- no duration recorded. Not backfilled, not required.
alter table public.training_sessions
  add column duration_seconds integer;

comment on column public.training_sessions.duration_seconds is
  'Wall-clock length of the match in seconds, from the scoreboard''s stopwatch. Nullable - not recorded for sessions saved before this column existed, or if the stopwatch result is unavailable.';

-- No RLS changes needed: RLS is row-level, not column-level. The existing
-- owner-only select/insert/delete policies from migration 0016 already
-- cover this new column automatically.
