-- ============================================================================
-- CSP Database — Migration 0002: Plan-Gating Helper Layer
-- Prompt 2 of 7 (builds on 0001_auth_profiles.sql)
-- ============================================================================
-- No feature tables yet (tournaments/club manager/magazine/table generator
-- all come in later prompts). This migration builds the central, reusable
-- gating layer those prompts will plug into via has_feature_access(),
-- can_create_tournament() and can_access_magazine_cms(), so plan logic is
-- never hardcoded separately across the five CSP apps.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. CLEAN SLATE
-- ----------------------------------------------------------------------------
-- Guarded so this migration can be re-run safely on top of a matching
-- 0001_auth_profiles.sql without needing to touch profiles/auth.users.
drop function if exists public.can_access_magazine_cms(uuid) cascade;
drop function if exists public.can_create_tournament(uuid) cascade;
drop function if exists public.remaining_tournament_quota(uuid) cascade;
drop function if exists public.has_feature_access(uuid, text) cascade;
drop table if exists public.feature_gates cascade;

-- ----------------------------------------------------------------------------
-- 1. tournaments_created_count on profiles
-- ----------------------------------------------------------------------------
-- Read-side only in this prompt: the counter and the quota functions below
-- exist now, but nothing increments the counter yet since the tournaments
-- table doesn't exist until prompt 3. Prompt 3 will attach a trigger on
-- `tournaments` (after insert) that increments this column.
alter table public.profiles
  add column if not exists tournaments_created_count integer not null default 0;

comment on column public.profiles.tournaments_created_count is
  'Lifetime count of tournaments created by this user, used to enforce the pro-tier 10-tournament cap. Incremented by a trigger on the tournaments table introduced in prompt 3 — this migration only adds the counter and the read-side quota functions below.';

-- ----------------------------------------------------------------------------
-- 2. feature_gates reference table
-- ----------------------------------------------------------------------------
-- Gating rules live in data, not scattered across app code or duplicated
-- RLS conditions. magazine_cms is intentionally NOT a row here: it is
-- admin-only and handled separately by can_access_magazine_cms(), not by
-- plan tier (ultra does not unlock it).
create table public.feature_gates (
  feature_key text primary key,
  min_plan text not null check (min_plan in ('free', 'pro', 'ultra')),
  description text
);

comment on table public.feature_gates is
  'Data-driven minimum-plan-per-feature lookup consumed by has_feature_access(). magazine_cms is deliberately absent — it is admin-only, see can_access_magazine_cms().';

insert into public.feature_gates (feature_key, min_plan, description) values
  ('train_scoreboards',        'free',  'Use training scoreboards.'),
  ('magazine_read',            'free',  'Read magazine articles.'),
  ('tournament_browse',        'free',  'Browse tournaments.'),
  ('tournament_self_register', 'free',  'Self-register into a tournament as a participant.'),
  ('tournament_create',        'pro',   'Create/organize a tournament (capped at 10 lifetime for pro, unlimited for ultra).'),
  ('club_manager',             'ultra', 'Access Club Manager (cspmanager.app).'),
  ('table_generator',          'ultra', 'Access the bracket/table generator (csptablegen.app).');

alter table public.feature_gates enable row level security;

-- Any authenticated user can read the gate table (the frontend needs it to
-- render locked/unlocked UI state across all five apps).
create policy feature_gates_select_authenticated
  on public.feature_gates
  for select
  to authenticated
  using (true);

-- Only admins can modify gating rules; no insert/update/delete for regular
-- users at all.
create policy feature_gates_write_admin
  on public.feature_gates
  for all
  to authenticated
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

grant select on public.feature_gates to authenticated;
grant insert, update, delete on public.feature_gates to authenticated;

-- ----------------------------------------------------------------------------
-- 3. has_feature_access(uid, key)
-- ----------------------------------------------------------------------------
-- The one function every later prompt's RLS policies should call, e.g.
-- prompt 5 (Club Manager) will write:
--   has_feature_access(auth.uid(), 'club_manager')
-- instead of re-deriving plan logic.
create function public.has_feature_access(uid uuid, key text)
returns boolean
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  required_plan text;
begin
  if public.is_admin(uid) then
    return true;
  end if;

  select min_plan into required_plan
  from public.feature_gates
  where feature_key = key;

  if required_plan is null then
    -- Unknown feature key: fail closed, not open, so a typo'd key can
    -- never accidentally unlock a feature it wasn't meant to.
    return false;
  end if;

  return public.has_plan_at_least(uid, required_plan);
end;
$$;

comment on function public.has_feature_access(uuid, text) is
  'Central plan-gating entry point for every later prompt''s RLS/UI, e.g. has_feature_access(auth.uid(), ''club_manager''). Admins always pass; unknown feature_key fails closed (returns false).';

-- ----------------------------------------------------------------------------
-- 4. Tournament creation quota (pro tier cap)
-- ----------------------------------------------------------------------------
-- The pro 10-tournament cap is a count, not a simple tier check, so it
-- needs its own read-side mechanism on top of has_feature_access().
create function public.remaining_tournament_quota(uid uuid)
returns integer
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  effective_plan text;
  used_count integer;
begin
  effective_plan := public.current_plan(uid);

  if effective_plan = 'ultra' then
    return null; -- unlimited; current_plan() already maps admins to 'ultra'
  end if;

  if effective_plan = 'free' then
    return 0; -- free cannot create tournaments at all
  end if;

  -- pro
  select coalesce(tournaments_created_count, 0)
  into used_count
  from public.profiles
  where id = uid;

  return greatest(10 - coalesce(used_count, 0), 0);
end;
$$;

comment on function public.remaining_tournament_quota(uuid) is
  'NULL = unlimited (ultra/admin). Otherwise the remaining pro-tier lifetime quota out of 10, floored at 0. Always 0 for free.';

create function public.can_create_tournament(uid uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select public.has_feature_access(uid, 'tournament_create')
     and (
       public.remaining_tournament_quota(uid) is null
       or public.remaining_tournament_quota(uid) > 0
     );
$$;

comment on function public.can_create_tournament(uuid) is
  'Convenience wrapper combining the tournament_create feature gate with the remaining pro-tier quota. Use this from tournament-creation RLS/UI rather than the two pieces separately. Note: incrementing tournaments_created_count is wired up in prompt 3 via a trigger on the tournaments table, which does not exist yet.';

-- ----------------------------------------------------------------------------
-- 5. Magazine CMS access (admin-only, not plan-gated)
-- ----------------------------------------------------------------------------
-- ultra does NOT unlock the CMS — this is a separate axis from plan tier.
-- Kept as its own named function (rather than inlining is_admin()
-- everywhere) purely for readability in prompt 6's magazine-CMS policies.
create function public.can_access_magazine_cms(uid uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select public.is_admin(uid);
$$;

comment on function public.can_access_magazine_cms(uuid) is
  'Magazine CMS write access is admin-only, independent of plan tier (ultra does not unlock it). Self-documenting alias for is_admin() used by prompt 6''s CMS RLS policies.';
