-- ============================================================================
-- CSP Database — Migration 0018: Events Table
-- ============================================================================
-- Numbering: checked `supabase migration list` against csp-staging first.
-- Highest CLI-tracked migration is 0017 (training_sessions_duration).
-- 0011-0013 are reserved in frontend comments for anticipated future schema
-- (stations/hourly_rate/events-v1 ideas from earlier prompts) but were
-- never applied via `db push` or the SQL Editor, so they remain untracked.
-- 0014 (articles.category) was applied directly via the SQL Editor as a
-- stray file at the repo root (outside supabase/migrations/) — it's
-- tracked there not here. This migration is therefore 0018.
--
-- Checked csp-staging directly (via PostgREST OpenAPI schema) before
-- writing: public.events does NOT exist. The table referenced as "0013"
-- in earlier frontend comments (udalost/index.html) was never actually
-- applied, confirming this is a fresh CREATE, not an ALTER.
--
-- OWNERSHIP NOTE — "same pattern as tournaments.club_id":
-- The spec references tournaments.club_id as the ownership-integrity
-- precedent for events.club_id. However, tournaments does not have a
-- club_id column in the live schema (confirmed via PostgREST). The actual
-- ownership-via-club_id pattern this repo uses is the RLS with check
-- already in stations and venues (migration 0005/0009): when club_id is
-- set, a with check confirms it belongs to a club owned by auth.uid().
-- This migration applies that same RLS-based check, extended to allow
-- club_id IS NULL (events.club_id is optional unlike stations/venues).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. CLEAN SLATE
-- ----------------------------------------------------------------------------
-- events is created by this migration itself — per the established pattern
-- (0001, 0005, 0009) no explicit DROP TRIGGER ... ON public.events here,
-- since IF EXISTS still requires the table to exist first. DROP TABLE
-- CASCADE below removes any triggers automatically.
drop table if exists public.events cascade;

-- ----------------------------------------------------------------------------
-- 1. EVENTS
-- ----------------------------------------------------------------------------
create table public.events (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null references public.profiles(id) on delete cascade,
  club_id      uuid references public.clubs(id) on delete set null,
  title        text not null,
  description  text,
  sport        text,
  discipline   text,           -- free text, same sport→discipline catalogue as Tournament Manager; not an enum
  location_text text,
  starts_at    timestamptz not null,
  ends_at      timestamptz,
  status       text not null default 'published'
               check (status in ('draft', 'published', 'cancelled')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on table public.events is
  'CSP events — tournaments, training days, social competitions, etc. Owner-managed, publicly browsable when status=published. club_id is optional (same event can exist without a club context). No RSVP/attendee list in this migration.';
comment on column public.events.club_id is
  'Optional FK to clubs. When set, must belong to a club owned by the same user who owns the event (enforced via RLS with check, the same pattern used for venues/stations). on delete set null: the event stays visible if its club is deleted.';
comment on column public.events.discipline is
  'Free text, optional. Matches the sport→discipline catalogue already used in Tournament Manager (e.g. sport=Biliard, discipline=8-ball) — not a separate concept, not an enum.';
comment on column public.events.status is
  'draft: only owner can see it. published: anyone (anon+authenticated) can see it. cancelled: only owner can see it.';

-- Reuses the shared updated_at stamper defined in 0001_auth_profiles.sql.
create trigger events_set_updated_at
  before update on public.events
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- 2. INDEXES
-- ----------------------------------------------------------------------------
create index events_owner_id_idx on public.events (owner_id);
create index events_club_id_idx on public.events (club_id);
-- Supports the primary public browse query: "upcoming published events, sorted soonest-first"
create index events_status_starts_at_idx on public.events (status, starts_at);

-- ----------------------------------------------------------------------------
-- 3. ROW LEVEL SECURITY
-- ----------------------------------------------------------------------------
alter table public.events enable row level security;

-- Owner CRUD on their own events (all statuses).
create policy events_owner_all
  on public.events
  for all
  to authenticated
  using (owner_id = auth.uid())
  with check (
    owner_id = auth.uid()
    -- club_id ownership integrity: if club_id is set, that club must belong
    -- to the same user. Mirrors the stations/venues RLS with check pattern
    -- (migrations 0005/0009), extended to allow club_id IS NULL since it's
    -- optional here (unlike stations/venues where it's required).
    and (
      club_id is null
      or exists (
        select 1 from public.clubs c
        where c.id = events.club_id and c.owner_id = auth.uid()
      )
    )
  );

-- Public (anon + authenticated) SELECT for published events only.
-- Same browse/spectate principle as migration 0010 (clubs, venues,
-- tournaments). Draft and cancelled events stay private to their owner.
create policy events_select_published
  on public.events
  for select
  to anon, authenticated
  using (status = 'published');

-- Grants: select + owner-write. No delete grant needed — the owner_all
-- policy's USING clause already controls row-level visibility for DELETE;
-- the table-level grant just needs to allow the operation.
grant select, insert, update, delete on public.events to authenticated;
grant select on public.events to anon;
