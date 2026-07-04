-- ============================================================================
-- CSP Database — Migration 0001: Auth + Profiles + Plan Tiers + RLS Core
-- Prompt 1 of 7
-- ============================================================================
-- Builds the foundation only: one unified profile per auth.users account,
-- subscription plan tiers (free/pro/ultra) plus a separate admin flag, and
-- the core RLS + helper functions later prompts (2-7) will build on top of.
-- Written to run top-to-bottom on a fresh Supabase project. Safe to re-run:
-- section 0 tears down any previous version of exactly this schema first.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. CLEAN SLATE
-- ----------------------------------------------------------------------------
-- Drop objects this migration is about to (re)create, in dependency order
-- (trigger -> function -> table -> type), guarded with IF EXISTS so this
-- runs cleanly on a brand new project as well as one that already has an
-- older copy of this same schema installed. This does NOT touch auth.users
-- itself or any other schema.
drop trigger if exists on_auth_user_created on auth.users;
drop trigger if exists profiles_set_updated_at on public.profiles;
drop trigger if exists profiles_protect_admin_columns on public.profiles;

drop function if exists public.handle_new_user() cascade;
drop function if exists public.set_updated_at() cascade;
drop function if exists public.protect_admin_only_columns() cascade;
drop function if exists public.is_admin(uuid) cascade;
drop function if exists public.current_plan(uuid) cascade;
drop function if exists public.has_plan_at_least(uuid, text) cascade;

drop table if exists public.profiles cascade;

drop type if exists public.profile_role cascade;
drop type if exists public.profile_plan cascade;

-- ----------------------------------------------------------------------------
-- 1. ENUM TYPES
-- ----------------------------------------------------------------------------
create type public.profile_role as enum ('player', 'club', 'organization');
create type public.profile_plan as enum ('free', 'pro', 'ultra');

-- ----------------------------------------------------------------------------
-- 2. PROFILES TABLE
-- ----------------------------------------------------------------------------
-- One row per auth.users account, shared across the whole CSP ecosystem
-- (connectsportspro.com + csptournament.app + cspmanager.app +
-- cspmagazine.app). There is deliberately no separate player/club/org
-- table — `role` only changes what the UI shows.
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  email text,
  role public.profile_role not null default 'player',
  plan public.profile_plan not null default 'free',
  is_admin boolean not null default false,
  plan_updated_at timestamptz not null default now(),
  plan_source text not null default 'manual',
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is
  'One row per auth.users account. Single unified profile shared across the whole CSP ecosystem (no separate player/club/org tables) — role only changes what the UI shows.';
comment on column public.profiles.email is
  'Mirrored from auth.users at signup time for convenient joins/queries. Not kept in sync automatically if the user later changes their auth email (out of scope for this prompt).';
comment on column public.profiles.role is
  'UI-facing role only (player/club/organization). Does not affect table structure or create duplicate profiles.';
comment on column public.profiles.plan is
  'Subscription tier: free/pro/ultra. Admin is intentionally NOT a plan value — see is_admin below, which is an orthogonal override.';
comment on column public.profiles.is_admin is
  'Cross-cutting super-user flag, independent of plan tier. Expected to be true for a very small number of accounts.';
comment on column public.profiles.plan_updated_at is
  'Timestamp of the last plan change. Auto-stamped by the protect_admin_only_columns trigger whenever an admin changes plan/plan_source.';
comment on column public.profiles.plan_source is
  'Where the current plan came from. Defaults to ''manual'' since there is no billing integration yet; leaves room for a future value such as ''stripe'' without a schema change.';
comment on column public.profiles.avatar_url is
  'Storage wiring lands in a later prompt (7); this column is just reserved for it now.';

create index profiles_plan_idx on public.profiles (plan);
create index profiles_role_idx on public.profiles (role);

-- ----------------------------------------------------------------------------
-- 3. AUTO-CREATE PROFILE ON SIGNUP
-- ----------------------------------------------------------------------------
-- Security definer: this runs as part of an auth.users insert, before the
-- new user has any session, so it must bypass profiles RLS to insert the
-- row on their behalf. Every signup must end up with exactly one profile —
-- no manual "create my profile" step should ever be required by a client.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, role, plan, is_admin)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'),
    'player',
    'free',
    false
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

comment on function public.handle_new_user() is
  'Fires after every auth.users insert so every signup ends up with exactly one profiles row (plan=free, role=player, is_admin=false), no frontend step required.';

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ----------------------------------------------------------------------------
-- 4. updated_at TRIGGER (reusable)
-- ----------------------------------------------------------------------------
-- Generic stamper with no table-specific logic. Later prompts (2-7) should
-- reuse this same function on every new table that has an updated_at
-- column, rather than defining their own copy.
create function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

comment on function public.set_updated_at() is
  'Generic updated_at stamper. Reuse on every future CSP table with an updated_at column (prompts 2-7) instead of duplicating this trigger function.';

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- 5. HELPER FUNCTIONS (security definer, reused by RLS in this + later prompts)
-- ----------------------------------------------------------------------------
-- These three are the foundation every later prompt's RLS policies build
-- gating on top of, so they are intentionally kept simple.

create function public.is_admin(uid uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select coalesce((select is_admin from public.profiles where id = uid), false);
$$;

comment on function public.is_admin(uuid) is
  'True if the given user''s profile has is_admin = true. Security definer so RLS policies elsewhere can call it without recursive-RLS issues on profiles itself.';

create function public.current_plan(uid uuid)
returns text
language sql
security definer
stable
set search_path = public
as $$
  select case
    when public.is_admin(uid) then 'ultra' -- admin always wins, regardless of stored plan
    else coalesce((select plan::text from public.profiles where id = uid), 'free')
  end;
$$;

comment on function public.current_plan(uid uuid) is
  'Effective plan for gating purposes. Admins are treated as ultra-or-better for feature access even if their plan column underneath still says free/pro/ultra.';

create function public.has_plan_at_least(uid uuid, required text)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select case public.current_plan(uid)
    when 'ultra' then true
    when 'pro' then required in ('free', 'pro')
    else required = 'free'
  end;
$$;

comment on function public.has_plan_at_least(uid uuid, required text) is
  'Encodes tier ordering free < pro < ultra so later prompts write has_plan_at_least(auth.uid(), ''pro'') instead of re-deriving ordering. Admins satisfy any tier via current_plan().';

-- ----------------------------------------------------------------------------
-- 6. PROTECT ADMIN-ONLY COLUMNS FROM SELF-EDIT
-- ----------------------------------------------------------------------------
-- A regular user is allowed (by the RLS policy below) to update their own
-- profile row for ordinary fields (full_name, avatar_url, role, ...), but
-- must never be able to grant themselves a plan upgrade or admin flag via
-- a normal client-side update. Postgres RLS has no native column-level
-- granularity for UPDATE without also wiring up column-level GRANTs and
-- extra roles, so a BEFORE UPDATE trigger is the simpler, single-place fix.
--
-- Tradeoff: this silently reverts the protected columns to their old
-- values for non-admins, rather than raising an exception. That means a
-- naive "send the whole row back on save" client won't get a hard failure
-- for a field it never intended to touch — but it also means a malicious
-- or buggy client attempting to self-upgrade fails silently instead of
-- loudly. If stricter behaviour is preferred later, swap the branch below
-- for `raise exception 'not allowed to change plan/admin columns'`.
create function public.protect_admin_only_columns()
returns trigger
language plpgsql
as $$
begin
  if not public.is_admin(auth.uid()) then
    new.plan := old.plan;
    new.is_admin := old.is_admin;
    new.plan_updated_at := old.plan_updated_at;
    new.plan_source := old.plan_source;
  elsif new.plan is distinct from old.plan or new.plan_source is distinct from old.plan_source then
    -- An admin actually changed the plan: stamp plan_updated_at
    -- automatically so callers never have to remember to set it.
    new.plan_updated_at := now();
  end if;

  return new;
end;
$$;

comment on function public.protect_admin_only_columns() is
  'Blocks non-admins from changing plan/is_admin/plan_updated_at/plan_source on their own row via a normal update; admins may change these on any row.';

create trigger profiles_protect_admin_columns
  before update on public.profiles
  for each row execute function public.protect_admin_only_columns();

-- ----------------------------------------------------------------------------
-- 7. ROW LEVEL SECURITY
-- ----------------------------------------------------------------------------
alter table public.profiles enable row level security;

-- Profiles are semi-public within the platform: any signed-in user can read
-- any profile (needed for player/club names in tournaments, standings,
-- magazine bylines, etc).
create policy profiles_select_authenticated
  on public.profiles
  for select
  to authenticated
  using (true);

-- A user may update only their own row. Which columns they're actually
-- allowed to change within that row is enforced by the trigger above, not
-- by this policy (Postgres RLS UPDATE policies are row-level, not
-- column-level).
create policy profiles_update_own
  on public.profiles
  for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- Admins may update any profile (e.g. to grant a plan change or admin
-- flag to another user).
create policy profiles_update_admin
  on public.profiles
  for update
  to authenticated
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

-- No INSERT policy for regular users: rows are created exclusively by the
-- handle_new_user() trigger (security definer), never directly by clients.
-- No DELETE policy at all, for anyone: profile deletion only ever happens
-- via the auth.users -> profiles ON DELETE CASCADE (account deletion flow).

grant select on public.profiles to authenticated;
grant update on public.profiles to authenticated;
