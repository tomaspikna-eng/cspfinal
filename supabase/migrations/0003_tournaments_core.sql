-- ============================================================================
-- CSP Database — Migration 0003: Tournaments, Players, Groups & Matches
-- Prompt 3 of 7 (builds on 0001_auth_profiles.sql, 0002_plan_gating.sql)
-- ============================================================================
-- Core tournament data model consumed by the Tournament Manager frontend
-- (csptournament_index.html). Match-addressing (round_key) mirrors the
-- frontend's existing localStorage scheme exactly (sko:r{round}:m{match},
-- rr:r{round}, {W|L|F}:{...}:{match}) — SQL stores it as opaque text and
-- does not re-derive or validate bracket structure. Standings stay a
-- client-side computation for now (see closing summary for known gaps).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. CLEAN SLATE
-- ----------------------------------------------------------------------------
-- Guarded so this migration can be re-run on top of a matching
-- 0001/0002 without touching profiles, feature_gates, or auth.users.
-- Note: triggers defined ON these tables (updated_at stampers, the quota
-- trigger) are not dropped explicitly — `DROP TABLE ... CASCADE` below
-- removes them for free, and (per the lesson from 0001) explicit
-- `DROP TRIGGER IF EXISTS x ON <table>` still errors if the table itself
-- doesn't exist yet on a fresh project.
drop function if exists public.increment_tournaments_created_count() cascade;

drop table if exists public.matches cascade;
drop table if exists public.tournament_groups cascade;
drop table if exists public.tournament_players cascade;
drop table if exists public.tournaments cascade;

-- ----------------------------------------------------------------------------
-- 1. TOURNAMENTS
-- ----------------------------------------------------------------------------
create table public.tournaments (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  sport text not null,
  discipline text not null,
  format text not null check (format in ('rr', 'sko', 'dko', 'rr_sko', 'rr_dko', 'karty')),
  date date,
  venue text,
  groups_count integer,
  advance_count integer,
  status text not null default 'draft' check (status in ('draft', 'active', 'completed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.tournaments is
  'One row per tournament created via the Tournament Manager frontend. Owner is the creator; draft tournaments are private until published (status changed away from draft).';
comment on column public.tournaments.groups_count is
  'Only meaningful when format is rr_sko / rr_dko; unused/null otherwise.';
comment on column public.tournaments.advance_count is
  'Only meaningful when format is rr_sko / rr_dko; unused/null otherwise.';

create index tournaments_owner_id_idx on public.tournaments (owner_id);

-- Reuses the shared updated_at stamper from 0001_auth_profiles.sql rather
-- than defining a new trigger function.
create trigger tournaments_set_updated_at
  before update on public.tournaments
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- 2. TOURNAMENT PLAYERS
-- ----------------------------------------------------------------------------
create table public.tournament_players (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  name text not null,
  user_id uuid references public.profiles(id) on delete set null,
  seed integer,
  created_at timestamptz not null default now()
);

comment on table public.tournament_players is
  'Entrants in a tournament. name is always stored (even for guests); user_id is null when the entrant is not a CSP account (a guest), and is set-null (not cascaded) if a linked account is later deleted so historical results are preserved.';

create index tournament_players_tournament_id_idx on public.tournament_players (tournament_id);

-- ----------------------------------------------------------------------------
-- 3. TOURNAMENT GROUPS (rr_sko / rr_dko formats only)
-- ----------------------------------------------------------------------------
create table public.tournament_groups (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  group_index integer not null,
  player_id uuid not null references public.tournament_players(id) on delete cascade
);

comment on table public.tournament_groups is
  'Group-stage membership for rr_sko/rr_dko tournaments. Deliberately has no stats columns (wins/played/etc) — standings are always computed from matches on read, never stored redundantly, to avoid a "forgot to rebuild derived stats" class of bug.';

create index tournament_groups_tournament_id_idx on public.tournament_groups (tournament_id);

-- ----------------------------------------------------------------------------
-- 4. MATCHES
-- ----------------------------------------------------------------------------
create table public.matches (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  round_key text not null,
  player1_id uuid references public.tournament_players(id) on delete set null,
  player2_id uuid references public.tournament_players(id) on delete set null,
  score1 integer,
  score2 integer,
  winner_id uuid references public.tournament_players(id) on delete set null,
  status text not null default 'pending' check (status in ('pending', 'live', 'completed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tournament_id, round_key)
);

comment on table public.matches is
  'One row per bracket/schedule slot. round_key is an opaque string in the frontend''s own addressing scheme (e.g. sko:r1:m1, rr:r1, W:A2:1) — SQL does not parse or validate it, only persists it. The frontend updates a row in place (via the unique (tournament_id, round_key) constraint) rather than inserting duplicates.';

create index matches_tournament_id_idx on public.matches (tournament_id);
-- The unique constraint above already provides an index usable for
-- (tournament_id, round_key) lookups; matches_tournament_id_idx additionally
-- supports plain "all matches for this tournament" queries efficiently.

create trigger matches_set_updated_at
  before update on public.matches
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- 5. WIRE UP THE TOURNAMENT-CREATION QUOTA (finishes prompt 2's placeholder)
-- ----------------------------------------------------------------------------
-- Security definer: the inserting user only has UPDATE rights on their own
-- profiles row via RLS, which happens to be sufficient here since owner_id
-- is always auth.uid() under the tournaments RLS insert policy below — but
-- definer keeps this robust even if a future prompt adds an admin-on-behalf
-- insert path. Increments unconditionally regardless of plan; this is a
-- lifetime counter for reporting only. The pro-tier cap is enforced by the
-- app calling can_create_tournament() *before* the insert, not here.
create function public.increment_tournaments_created_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles
  set tournaments_created_count = tournaments_created_count + 1
  where id = new.owner_id;

  return new;
end;
$$;

comment on function public.increment_tournaments_created_count() is
  'Increments profiles.tournaments_created_count for the owner of every new tournament, unconditionally. Cap enforcement (can_create_tournament()) happens app-side before the insert, not in this trigger.';

create trigger tournaments_increment_owner_count
  after insert on public.tournaments
  for each row execute function public.increment_tournaments_created_count();

-- ----------------------------------------------------------------------------
-- 6. ROW LEVEL SECURITY
-- ----------------------------------------------------------------------------

-- ---- tournaments ----
alter table public.tournaments enable row level security;

-- Owner has full CRUD on their own tournaments (including drafts).
create policy tournaments_owner_all
  on public.tournaments
  for all
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- Anyone authenticated can browse/self-register into published tournaments.
-- Draft tournaments stay private to the owner (covered by the policy above).
create policy tournaments_select_published
  on public.tournaments
  for select
  to authenticated
  using (status <> 'draft');

grant select, insert, update, delete on public.tournaments to authenticated;

-- ---- tournament_players ----
alter table public.tournament_players enable row level security;

-- Readable by anyone who can read the parent tournament (owner, or anyone
-- when the tournament is published).
create policy tournament_players_select
  on public.tournament_players
  for select
  to authenticated
  using (
    exists (
      select 1 from public.tournaments t
      where t.id = tournament_players.tournament_id
        and (t.owner_id = auth.uid() or t.status <> 'draft')
    )
  );

-- Only the tournament owner may add/edit/remove entrants.
create policy tournament_players_owner_write
  on public.tournament_players
  for all
  to authenticated
  using (
    exists (
      select 1 from public.tournaments t
      where t.id = tournament_players.tournament_id
        and t.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.tournaments t
      where t.id = tournament_players.tournament_id
        and t.owner_id = auth.uid()
    )
  );

grant select, insert, update, delete on public.tournament_players to authenticated;

-- ---- tournament_groups ----
alter table public.tournament_groups enable row level security;

-- Same visibility rule as tournament_players: public read through the
-- parent tournament, owner-only write.
create policy tournament_groups_select
  on public.tournament_groups
  for select
  to authenticated
  using (
    exists (
      select 1 from public.tournaments t
      where t.id = tournament_groups.tournament_id
        and (t.owner_id = auth.uid() or t.status <> 'draft')
    )
  );

create policy tournament_groups_owner_write
  on public.tournament_groups
  for all
  to authenticated
  using (
    exists (
      select 1 from public.tournaments t
      where t.id = tournament_groups.tournament_id
        and t.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.tournaments t
      where t.id = tournament_groups.tournament_id
        and t.owner_id = auth.uid()
    )
  );

grant select, insert, update, delete on public.tournament_groups to authenticated;

-- ---- matches ----
alter table public.matches enable row level security;

-- Public read through the parent tournament, same rule as above.
create policy matches_select
  on public.matches
  for select
  to authenticated
  using (
    exists (
      select 1 from public.tournaments t
      where t.id = matches.tournament_id
        and (t.owner_id = auth.uid() or t.status <> 'draft')
    )
  );

-- INSERT/UPDATE restricted to the tournament owner for now. Deliberately no
-- DELETE policy and no player-self-confirmation policy yet — see summary
-- for this known gap; a later prompt will design the double-confirmation
-- workflow before opening any write access to non-owners.
create policy matches_insert_owner
  on public.matches
  for insert
  to authenticated
  with check (
    exists (
      select 1 from public.tournaments t
      where t.id = matches.tournament_id
        and t.owner_id = auth.uid()
    )
  );

create policy matches_update_owner
  on public.matches
  for update
  to authenticated
  using (
    exists (
      select 1 from public.tournaments t
      where t.id = matches.tournament_id
        and t.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.tournaments t
      where t.id = matches.tournament_id
        and t.owner_id = auth.uid()
    )
  );

-- No delete grant either: matches are corrected via UPDATE (owner sets
-- score/status back to pending/live), not removed, until a later prompt
-- decides deletion is actually needed.
grant select, insert, update on public.matches to authenticated;
