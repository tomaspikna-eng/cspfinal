-- ============================================================================
-- CSP Database — Migration 0015: Add "Elite" Plan Tier
-- ============================================================================
-- Unifies pricing into a single 4-tier ladder for everyone:
--   free < pro < ultra < elite
-- replacing the earlier role-based split (players had free/pro; clubs and
-- organizations had free/ultra). No new feature_gates rows are added
-- here — elite-specific feature gating isn't designed yet; this
-- migration only makes `elite` a valid, correctly-ordered plan value.
--
-- IMPORTANT — two things verified live against csp-staging before
-- writing this, both of which turned out to differ from what a naive
-- reading of the task might assume:
--
-- 1. `profiles.plan` is NOT a `text` column with a check constraint
--    named `profiles_plan_check`. It's a genuine Postgres ENUM type,
--    `public.profile_plan` (created in migration 0001), currently
--    `('free', 'pro', 'ultra')` — confirmed via
--    `information_schema.columns` (data_type = 'USER-DEFINED', udt_name
--    = 'profile_plan') and `pg_enum`. There is no `profiles_plan_check`
--    constraint to drop/recreate at all (confirmed empty result from
--    pg_constraint). The correct, and only, way to add a new value is
--    `ALTER TYPE ... ADD VALUE`, not a check-constraint rewrite.
--
-- 2. `current_plan(uid)` (also from migration 0001) hardcodes admins to
--    the literal string 'ultra', not "whatever the current top tier is":
--
--      select case
--        when public.is_admin(uid) then 'ultra' -- admin always wins, regardless of stored plan
--        else coalesce((select plan::text from public.profiles where id = uid), 'free')
--      end;
--
--    The non-admin branch just returns the raw column value, so it
--    already handles 'elite' correctly once the enum allows it — no
--    change needed there, as the task assumed. But the admin branch
--    does need a change: `has_plan_at_least()`'s ENTIRE original tier
--    logic (see verbatim quote below) worked by mapping the single
--    highest tier to `true` unconditionally. If current_plan() keeps
--    returning 'ultra' for admins after 'elite' becomes a real tier
--    above it, admins would FAIL a has_plan_at_least(admin_uid, 'elite')
--    check — silently breaking the existing "admins satisfy any tier"
--    guarantee this same function's own comment promises. Updating the
--    admin branch to 'elite' is the minimal change needed to preserve
--    that guarantee unchanged under the new top tier, not new behavior.
--
-- Original has_plan_at_least() body, verbatim, confirmed live via
-- pg_get_functiondef before this migration (for the record):
--
--   select case public.current_plan(uid)
--     when 'ultra' then true
--     when 'pro' then required in ('free', 'pro')
--     else required = 'free'
--   end;
--
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. EXTEND THE ENUM (not a check constraint — see note above)
-- ----------------------------------------------------------------------------
-- ADD VALUE IF NOT EXISTS makes this safe to re-run. Not combined with
-- any statement that uses the literal 'elite' value in this same
-- migration/transaction (Postgres restricts using a brand new enum
-- label within the transaction that added it in some contexts) — the
-- functions below only ever compare against `required`/`current_plan()`
-- as plain text, never an enum literal, so this ordering is safe
-- regardless.
alter type public.profile_plan add value if not exists 'elite';

-- ----------------------------------------------------------------------------
-- 2. current_plan() — update the admin-bypass branch only
-- ----------------------------------------------------------------------------
-- Non-admin branch (coalesce of the raw plan column, cast to text) is
-- completely unchanged — it already returns 'elite' correctly once the
-- enum allows it, exactly as the task expected. Only the hardcoded admin
-- literal changes, from 'ultra' to 'elite', so admins keep satisfying
-- every tier check after 'elite' becomes the real top tier (see header
-- comment for why this is necessary, not optional).
create or replace function public.current_plan(uid uuid)
returns text
language sql
security definer
stable
set search_path = public
as $$
  select case
    when public.is_admin(uid) then 'elite' -- admin always wins, now against the new top tier too
    else coalesce((select plan::text from public.profiles where id = uid), 'free')
  end;
$$;

comment on function public.current_plan(uid uuid) is
  'Effective plan for gating purposes. Admins are treated as elite-or-better for feature access even if their plan column underneath still says free/pro/ultra/elite.';

-- ----------------------------------------------------------------------------
-- 3. has_plan_at_least() — extend the tier ordering with elite on top
-- ----------------------------------------------------------------------------
-- Same CREATE OR REPLACE, exact same signature (uid uuid, required
-- text), so every existing RLS policy that already calls it picks up
-- the new tier automatically. 'ultra' no longer unconditionally returns
-- true (it now only satisfies free/pro/ultra, not elite) — 'elite' takes
-- over the "top tier always satisfies" role that 'ultra' used to have.
create or replace function public.has_plan_at_least(uid uuid, required text)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select case public.current_plan(uid)
    when 'elite' then true
    when 'ultra' then required in ('free', 'pro', 'ultra')
    when 'pro' then required in ('free', 'pro')
    else required = 'free'
  end;
$$;

comment on function public.has_plan_at_least(uid uuid, required text) is
  'Encodes tier ordering free < pro < ultra < elite so later code writes has_plan_at_least(auth.uid(), ''pro'') instead of re-deriving ordering. Admins satisfy any tier via current_plan() mapping them to elite (the top tier).';
