-- ============================================================================
-- CSP Database — Migration 0016: Training Session History
-- ============================================================================
-- Numbering note: the next free sequential number after 0010 is 0016, not
-- 0011 or 0016 - 1 = 0015 + 1. Checked `supabase migration list` against
-- csp-staging first: it shows 0001-0010 and 0015 as the only migrations
-- actually tracked by the CLI. 0011, 0012, 0013 and 0014 are all already
-- spoken for even though they never went through `db push`/git as their
-- own tracked migration: 0011 (tournament_players/tournament_groups
-- additions, referenced in turnament/index.html), 0012 (venues hourly_rate,
-- referenced in manager/rezervacie/index.html, anticipated/not yet applied)
-- and 0013 (an `events` table, referenced in udalost/index.html, likewise
-- anticipated/not yet applied) were reserved in frontend comments for
-- specific future schema; 0014 (articles.category) was applied directly
-- via the SQL Editor and left behind as a stray `0014_article_categories.sql`
-- file at the repo root (outside supabase/migrations/, hence invisible to
-- `migration list`). None of those numbers are safe to reuse, so this
-- migration is 0016.
--
-- Continues the CSP Supabase backend (same repo, same csp-staging
-- project). The standalone scoreboard tool (scoreboard/index.html) has no
-- way to save a finished match to history today - purely live/ephemeral
-- localStorage state, reset on "Nový zápas". This is a *personal profile*
-- feature: only meaningful for a logged-in individual doing personal
-- training. Anonymous station usage (the QR/club-station tablet flow,
-- migration 0005) simply won't save anything here - that is correct
-- behavior, not a gap, since there's no owner to attribute a session to.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. CLEAN SLATE
-- ----------------------------------------------------------------------------
-- training_sessions is created by this migration itself, so - same lesson
-- as 0001/0005/0009 - no explicit `DROP TRIGGER ... ON public.training_sessions`
-- here (IF EXISTS still requires the table to exist, which it won't on a
-- fresh run). `DROP TABLE ... CASCADE` below removes any triggers for free.
drop table if exists public.training_sessions cascade;

-- ----------------------------------------------------------------------------
-- 1. TRAINING_SESSIONS
-- ----------------------------------------------------------------------------
create table public.training_sessions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  sport text not null,
  discipline text not null,
  player_names text[] not null,
  final_score jsonb not null,
  winner_name text,
  race_to integer,
  played_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

comment on table public.training_sessions is
  'Finished personal scoreboard sessions (scoreboard/index.html), saved to a logged-in user''s own history. Deliberately standalone - no relationship to tournaments/matches, same reasoning as events being kept separate from tournaments. Anonymous club-station usage (migration 0005) never writes here, since there is no owner to attribute a session to.';
comment on column public.training_sessions.player_names is
  '2-3 names exactly as typed into the scoreboard at play time - not necessarily other CSP accounts, no FK to profiles/tournament_players.';
comment on column public.training_sessions.final_score is
  'Flexible shape: frames/legs/sets/points per player, varies by sport/mode. Deliberately jsonb, not normalized columns, so it isn''t over-constrained to one scoring shape.';
comment on column public.training_sessions.winner_name is
  'Nullable - a session could theoretically be saved without a clearly resolved winner name.';
comment on column public.training_sessions.race_to is
  'The target score/race configured for the session, if the mode used one. Nullable for modes without a fixed target.';

-- Supports the obvious "my recent training history" query pattern:
-- select * from training_sessions where owner_id = ... order by played_at desc.
create index training_sessions_owner_played_at_idx
  on public.training_sessions (owner_id, played_at desc);

-- ----------------------------------------------------------------------------
-- 2. ROW LEVEL SECURITY
-- ----------------------------------------------------------------------------
alter table public.training_sessions enable row level security;

-- Owner-only, and deliberately only insert/select/delete - no update
-- policy. A finished session is a historical record, not something to
-- edit after the fact; if it's wrong, delete and re-log it. No public/
-- anon SELECT policy either - personal stats only, not meant to be
-- publicly browsable through this table.
create policy training_sessions_select_owner
  on public.training_sessions
  for select
  to authenticated
  using (owner_id = auth.uid());

create policy training_sessions_insert_owner
  on public.training_sessions
  for insert
  to authenticated
  with check (owner_id = auth.uid());

create policy training_sessions_delete_owner
  on public.training_sessions
  for delete
  to authenticated
  using (owner_id = auth.uid());

grant select, insert, delete on public.training_sessions to authenticated;
