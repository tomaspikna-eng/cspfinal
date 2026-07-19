-- ============================================================================
-- CSP Database — Migration 0019: Venue Pricing Rules + Billable Sessions
-- ============================================================================
-- Numbering: checked `supabase migration list` against csp-staging first.
-- Highest CLI-tracked migration is 0018 (events). 0011-0014 remain known
-- reserved/untracked gaps (some work was applied through the SQL Editor),
-- so 0019 is the next safe sequential filename.
--
-- set_updated_at() was verified before writing this migration: it is the
-- existing shared public.set_updated_at() trigger function created in
-- 0001_auth_profiles.sql and already reused by clubs (0005), stations
-- (0005), and venues (0009).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. CLEAN SLATE
-- ----------------------------------------------------------------------------
-- Both tables are created by this migration. As in 0001/0005/0009, do not
-- issue DROP TRIGGER ... ON a table that may not exist yet; DROP TABLE ...
-- CASCADE removes any prior trigger state safely on a rerun.
drop table if exists public.venue_sessions cascade;
drop table if exists public.venue_pricing_rules cascade;

-- ----------------------------------------------------------------------------
-- 1. VENUE PRICING RULES
-- ----------------------------------------------------------------------------
-- Rules are intentionally flexible: staff selects guest_tier when starting
-- a session; there is no club-membership/member database lookup. Multiple
-- rules may overlap, and priority is deliberately manual (higher checked
-- first) rather than auto-computed because organisers, not the database,
-- decide which special offer should win.
create table public.venue_pricing_rules (
  id          uuid primary key default gen_random_uuid(),
  venue_id    uuid not null references public.venues(id) on delete cascade,
  guest_tier  text not null check (guest_tier in ('walkin', 'vip', 'member')),
  day_of_week int check (day_of_week between 0 and 6),
  time_start  time,
  time_end    time,
  hourly_rate numeric(10,2) not null,
  label       text,
  priority    int not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.venue_pricing_rules is
  'Organizer-defined venue pricing rules. Guest tier is selected manually by staff at session start; no member database exists. Overlapping rules are intentionally resolved by manually configured priority (higher first).';
comment on column public.venue_pricing_rules.day_of_week is
  '0-6 day-of-week filter; NULL means every day.';
comment on column public.venue_pricing_rules.time_start is
  'Optional time-window start; NULL means no start restriction.';
comment on column public.venue_pricing_rules.time_end is
  'Optional time-window end; NULL means no end restriction.';
comment on column public.venue_pricing_rules.priority is
  'Manual overlap resolution. Higher priority rules are checked first; never auto-computed.';

-- Confirmed existing shared function: public.set_updated_at() from 0001.
create trigger venue_pricing_rules_set_updated_at
  before update on public.venue_pricing_rules
  for each row execute function public.set_updated_at();

create index venue_pricing_rules_venue_id_idx
  on public.venue_pricing_rules (venue_id);

-- ----------------------------------------------------------------------------
-- 2. BILLABLE VENUE SESSIONS
-- ----------------------------------------------------------------------------
-- stopped_at NULL marks a running session. hourly_rate_applied and
-- total_amount are snapshots written at Stop time, so historical bills do
-- not change if an organizer later edits the pricing rules.
create table public.venue_sessions (
  id                  uuid primary key default gen_random_uuid(),
  venue_id            uuid not null references public.venues(id) on delete cascade,
  guest_tier          text not null check (guest_tier in ('walkin', 'vip', 'member')),
  started_at          timestamptz not null default now(),
  stopped_at          timestamptz,
  hourly_rate_applied numeric(10,2),
  total_amount        numeric(10,2),
  entered_to_till     boolean not null default false,
  created_by          uuid references public.profiles(id) on delete set null,
  created_at          timestamptz not null default now()
);

comment on table public.venue_sessions is
  'Start/Stop billable venue sessions. stopped_at NULL means still running for a future live-occupancy view. Rate and total are snapshots retained after pricing rules change.';
comment on column public.venue_sessions.hourly_rate_applied is
  'Rate snapshot actually used on Stop; nullable while running.';
comment on column public.venue_sessions.total_amount is
  'Amount calculated on Stop; nullable while running.';
comment on column public.venue_sessions.entered_to_till is
  'Manual staff confirmation that the completed session was recorded in the till.';

create index venue_sessions_venue_id_idx
  on public.venue_sessions (venue_id);
create index venue_sessions_running_venue_id_idx
  on public.venue_sessions (venue_id)
  where stopped_at is null;

-- ----------------------------------------------------------------------------
-- 3. ROW LEVEL SECURITY
-- ----------------------------------------------------------------------------
-- Exact existing venue/station ownership chain: current user -> club owner
-- -> venue. This is intentionally not based on created_by: Club Control
-- ownership is the club organizer's scope, regardless of which staff member
-- recorded a particular session.
alter table public.venue_pricing_rules enable row level security;
alter table public.venue_sessions enable row level security;

create policy venue_pricing_rules_owner_all
  on public.venue_pricing_rules
  for all
  to authenticated
  using (
    exists (
      select 1
      from public.venues v
      join public.clubs c on c.id = v.club_id
      where v.id = venue_pricing_rules.venue_id
        and c.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.venues v
      join public.clubs c on c.id = v.club_id
      where v.id = venue_pricing_rules.venue_id
        and c.owner_id = auth.uid()
    )
  );

create policy venue_sessions_owner_all
  on public.venue_sessions
  for all
  to authenticated
  using (
    exists (
      select 1
      from public.venues v
      join public.clubs c on c.id = v.club_id
      where v.id = venue_sessions.venue_id
        and c.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.venues v
      join public.clubs c on c.id = v.club_id
      where v.id = venue_sessions.venue_id
        and c.owner_id = auth.uid()
    )
  );

grant select, insert, update, delete on public.venue_pricing_rules to authenticated;
grant select, insert, update, delete on public.venue_sessions to authenticated;
