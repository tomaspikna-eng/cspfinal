-- ============================================================================
-- CSP Database — Migration 0005: Club Manager — Clubs & Stations
-- Prompt 5 of 7 (builds on 0001-0004)
-- ============================================================================
-- Backend for the existing Stations tool only (cspmanager.app): a club
-- owner creates stations (one per physical table/dart board); each station
-- gets an unguessable token used in its QR code URL; an anonymous tablet
-- that scans the code can read that one station's public info by token,
-- nothing else. No members/roster, no reservations, no league linkage —
-- explicitly out of scope for this prompt.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. CLEAN SLATE
-- ----------------------------------------------------------------------------
-- clubs/stations are created by this migration itself (unlike 0003-0004,
-- which extended tables from earlier prompts), so — same lesson learned in
-- 0001 — explicit `DROP TRIGGER ... ON public.clubs/stations` is not used
-- here, since IF EXISTS still requires the *table* to exist and it won't
-- on a truly fresh run. `DROP TABLE ... CASCADE` below removes any
-- triggers for free.
drop function if exists public.get_station_by_token(text) cascade;
drop function if exists public.enforce_club_manager_access() cascade;

drop table if exists public.stations cascade;
drop table if exists public.clubs cascade;

-- ----------------------------------------------------------------------------
-- 1. ENSURE pgcrypto IS ENABLED (needed for gen_random_bytes)
-- ----------------------------------------------------------------------------
-- gen_random_uuid() used elsewhere in this schema is built into Postgres
-- core since v13 and needs no extension, but gen_random_bytes() (used
-- below for station tokens) is pgcrypto-specific. Confirmed live on this
-- project: pgcrypto is already enabled in the `extensions` schema (the
-- Supabase default) — this statement is a no-op in that case, but is
-- kept so a brand new project without it enabled still works.
create extension if not exists pgcrypto with schema extensions;

-- The `extensions` schema isn't necessarily on every role's search_path,
-- so gen_random_bytes() is called schema-qualified below rather than
-- relying on search_path to find it.

-- ----------------------------------------------------------------------------
-- 2. CLUBS
-- ----------------------------------------------------------------------------
create table public.clubs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.clubs is
  'A club owned by exactly one profile, gated behind the club_manager feature (currently ultra-tier). No public read access — club existence/name is not listable through this table (out of scope: a public club directory).';

create index clubs_owner_id_idx on public.clubs (owner_id);

-- Reuses the shared updated_at stamper from 0001_auth_profiles.sql.
create trigger clubs_set_updated_at
  before update on public.clubs
  for each row execute function public.set_updated_at();

-- Blocks club creation outright for accounts without club_manager access,
-- with a clear error rather than a silent failure. Reuses
-- has_feature_access() from prompt 2 rather than re-deriving plan logic.
create function public.enforce_club_manager_access()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_feature_access(auth.uid(), 'club_manager') then
    raise exception 'Club Manager access required to create a club.';
  end if;

  return new;
end;
$$;

comment on function public.enforce_club_manager_access() is
  'Blocks INSERT on clubs unless has_feature_access(auth.uid(), ''club_manager'') is true (currently ultra-tier or admin).';

create trigger clubs_enforce_feature_access
  before insert on public.clubs
  for each row execute function public.enforce_club_manager_access();

-- ----------------------------------------------------------------------------
-- 3. STATIONS
-- ----------------------------------------------------------------------------
create table public.stations (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  name text not null,
  sport text not null check (sport in ('billiard', 'darts')),
  token text not null unique default encode(extensions.gen_random_bytes(16), 'hex'),
  lock_mode boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.stations is
  'One row per physical table/dart board. token is an unguessable 32-char hex string (never a sequential id) used in that station''s QR code URL; regenerate it (update the column) to invalidate a previously issued code. No public read access here either — see get_station_by_token() for how an anonymous tablet reads a station instead.';
comment on column public.stations.token is
  'Unguessable lookup key for anonymous QR-code access via get_station_by_token(). Unique constraint below also provides its lookup index.';
comment on column public.stations.lock_mode is
  'True once a tablet has scanned this station''s code and should stay locked to it.';

create index stations_club_id_idx on public.stations (club_id);

create trigger stations_set_updated_at
  before update on public.stations
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- 4. ROW LEVEL SECURITY — OWNER SIDE
-- ----------------------------------------------------------------------------
alter table public.clubs enable row level security;

-- Owner has full CRUD on their own clubs. No SELECT policy for anyone
-- else — deliberately no public/anon read access on this table.
create policy clubs_owner_all
  on public.clubs
  for all
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

grant select, insert, update, delete on public.clubs to authenticated;

alter table public.stations enable row level security;

-- Owner has full CRUD on stations belonging to their own club(s). No
-- public/anon SELECT policy here either — see section 5 for how an
-- anonymous tablet reads a single station's public info instead.
create policy stations_owner_all
  on public.stations
  for all
  to authenticated
  using (
    exists (
      select 1 from public.clubs c
      where c.id = stations.club_id and c.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.clubs c
      where c.id = stations.club_id and c.owner_id = auth.uid()
    )
  );

grant select, insert, update, delete on public.stations to authenticated;

-- ----------------------------------------------------------------------------
-- 5. ANONYMOUS STATION LOOKUP (function, not a public SELECT policy)
-- ----------------------------------------------------------------------------
-- Deliberately not a public/anon RLS SELECT policy on stations — that
-- would let anyone list every station by querying with no filter,
-- defeating the "unguessable token" design. This function is the only
-- anonymous read path: it returns at most one row, by exact token match,
-- with only the public-safe fields a scoreboard tablet needs.
create function public.get_station_by_token(lookup_token text)
returns table (name text, sport text, lock_mode boolean, club_name text)
language sql
security definer
stable
set search_path = public
as $$
  select s.name, s.sport, s.lock_mode, c.name as club_name
  from public.stations s
  join public.clubs c on c.id = s.club_id
  where s.token = lookup_token;
$$;

comment on function public.get_station_by_token(text) is
  'The only anonymous read path onto stations: returns public-safe fields for exactly one token match (or zero rows if no match), never a list. Called by the anon role from the QR-code landing page.';

grant usage on schema public to anon;
grant execute on function public.get_station_by_token(text) to anon, authenticated;
