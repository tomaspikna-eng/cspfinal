-- ============================================================================
-- CSP Database — Migration 0009: Club Venues (Športoviská)
-- Prompt 9 (builds on 0001-0008, in particular 0005's clubs/stations)
-- ============================================================================
-- `venues` is a separate, broader concept from `stations` (migration
-- 0005): a venue is the physical court/lane/room itself (informational —
-- name, sport, description, an optional member-facing tip), not a
-- QR-linked scoreboard. A station's scoreboard could theoretically live
-- inside a venue someday, but that relationship is explicitly not
-- designed here — the two tables stay fully independent. `stations` is
-- not touched by this migration at all.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. CLEAN SLATE
-- ----------------------------------------------------------------------------
-- venues is created by this migration itself, so — same lesson as 0001
-- and 0005 — no explicit `DROP TRIGGER ... ON public.venues` here (IF
-- EXISTS still requires the table to exist, which it won't on a fresh
-- run). `DROP TABLE ... CASCADE` below removes any triggers for free.
drop table if exists public.venues cascade;

-- ----------------------------------------------------------------------------
-- 1. VENUES
-- ----------------------------------------------------------------------------
create table public.venues (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  name text not null,
  sport text,
  description text,
  tip text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.venues is
  'A club''s actual playing areas (courts/lanes/rooms) — informational/descriptive, independent of the stations QR-scoreboard system (migration 0005). No FK between the two tables by design.';
comment on column public.venues.sport is
  'Free text, not a fixed enum — clubs may host any discipline, including ones CSP hasn''t formally modeled yet.';
comment on column public.venues.description is
  'What the venue is / what''s in it (e.g. "2 stoly, klimatizované").';
comment on column public.venues.tip is
  'Optional hint shown to members, e.g. booking advice ("Rezervuj cez recepciu do 18:00").';

create index venues_club_id_idx on public.venues (club_id);

-- Reuses the shared updated_at stamper from 0001_auth_profiles.sql.
create trigger venues_set_updated_at
  before update on public.venues
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- 2. ROW LEVEL SECURITY
-- ----------------------------------------------------------------------------
alter table public.venues enable row level security;

-- Same ownership pattern as stations (migration 0005): owner has full
-- CRUD on venues belonging to their own club(s). No public/anon SELECT
-- policy — a public club directory, if built later, is a separate
-- design task.
create policy venues_owner_all
  on public.venues
  for all
  to authenticated
  using (
    exists (
      select 1 from public.clubs c
      where c.id = venues.club_id and c.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.clubs c
      where c.id = venues.club_id and c.owner_id = auth.uid()
    )
  );

grant select, insert, update, delete on public.venues to authenticated;
