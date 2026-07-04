-- ============================================================================
-- CSP Database — Migration 0004: Match Self-Confirmation (Double Confirmation)
-- Prompt 4 of 7 (builds on 0001-0003, extends the existing `matches` table)
-- ============================================================================
-- Players report their own match result; if both sides' reports agree, the
-- match auto-confirms with no organizer action. If they disagree, the
-- match is flagged `disputed` for the tournament owner to resolve manually
-- via their existing (prompt 3) owner-write path.
--
-- IMPORTANT — flagged assumption about score semantics (please confirm):
-- The prompt text describes both `player1_reported_score` and
-- `player2_reported_score` as holding "games/points won overall by
-- player1", compared directly for equality to decide auto-confirm vs
-- dispute. Taken completely literally, that can't be correct: if both
-- columns track the *same* target number and must be numerically equal to
-- auto-confirm, then score1 and score2 would always end up equal on every
-- auto-confirmation, which makes winner_id (explicitly required by this
-- same prompt) mathematically undeterminable. That's a direct
-- contradiction, so it cannot be what's intended as written.
--
-- The interpretation implemented here instead (and the only one that is
-- internally consistent with "derive score1 AND score2, infer which
-- reported column maps to which player consistently", the RLS
-- restriction that each side may only ever write their *own* reporting
-- column, and a real winner_id being derivable) is:
--   player1_reported_score  = player1's own reported tally  -> becomes score1
--   player2_reported_score  = player2's own reported tally  -> becomes score2
-- i.e. each side self-reports their own side of the result (the same unit
-- score1/score2 already use — games/points/sets, whichever the frontend
-- uses there, unchanged from prompt 3). Under this model "agreement" is
-- reframed from a literal number-for-number match into "both sides have
-- reported and the result is decisive" (score1 <> score2, a real winner
-- exists) -> auto-confirm; "both reported but numerically tied" (no
-- derivable winner, an anomalous/ambiguous outcome for what is presumably
-- a decisive race-to-N format) -> disputed, left for the owner to resolve.
-- If the frontend's real convention for reporting a self-score differs
-- from this (e.g. it actually submits a shared/derived value rather than
-- each side's own tally), this trigger's comparison logic will need a
-- follow-up migration once that's confirmed — nothing else in this file
-- (columns, indexes, RLS shape) would need to change.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. CLEAN SLATE
-- ----------------------------------------------------------------------------
-- public.matches already exists from 0003 by the time this migration runs,
-- so (unlike 0001's fresh-project trigger-drop issue) dropping a trigger
-- "on public.matches" here is always safe.
drop trigger if exists matches_handle_self_report on public.matches;
drop function if exists public.handle_match_self_report() cascade;

drop policy if exists matches_self_report on public.matches;

alter table public.matches drop constraint if exists matches_status_check;

alter table public.matches
  drop column if exists player1_reported_score,
  drop column if exists player1_reported_at,
  drop column if exists player2_reported_score,
  drop column if exists player2_reported_at;

-- ----------------------------------------------------------------------------
-- 1. REPORTING COLUMNS
-- ----------------------------------------------------------------------------
alter table public.matches
  add column player1_reported_score integer,
  add column player1_reported_at timestamptz,
  add column player2_reported_score integer,
  add column player2_reported_at timestamptz;

comment on column public.matches.player1_reported_score is
  'Player1''s own self-reported tally (same unit as score1: games/points/sets, whichever the frontend already uses there). Settable only by the auth.uid() linked to tournament_players.player1_id. See migration header for the assumption this rests on.';
comment on column public.matches.player2_reported_score is
  'Player2''s own self-reported tally (same unit as score2). Settable only by the auth.uid() linked to tournament_players.player2_id.';

-- ----------------------------------------------------------------------------
-- 2. EXTEND status CHECK CONSTRAINT
-- ----------------------------------------------------------------------------
alter table public.matches
  add constraint matches_status_check check (status in ('pending', 'live', 'completed', 'disputed'));

-- ----------------------------------------------------------------------------
-- 3 & 4. COLUMN PROTECTION + AUTO-CONFIRMATION (combined trigger)
-- ----------------------------------------------------------------------------
-- Combined into one BEFORE UPDATE trigger because the two concerns are
-- sequential: first sanitise who's allowed to touch which columns on this
-- update, then (using the now-sanitised NEW row) decide whether the
-- reported columns changing should recompute score1/score2/winner_id/status.
--
-- Column-level RLS tradeoff: same pattern as protect_admin_only_columns()
-- in prompt 1 — Postgres RLS UPDATE policies can't restrict *which*
-- columns a request touches, only *which rows* it may touch. A
-- self-reporting player's UPDATE is allowed at the row level by the new
-- matches_self_report policy below, and this trigger then silently
-- reverts any column they're not allowed to change (everything except
-- their own report score/timestamp) rather than hard-failing the whole
-- statement, so a client that sends back more of the row than intended
-- doesn't get an error for the part it didn't mean to change.
create function public.handle_match_self_report()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner_id uuid;
  v_privileged boolean;
  v_player1_user uuid;
  v_player2_user uuid;
  v_is_p1_reporter boolean;
  v_is_p2_reporter boolean;
begin
  select owner_id into v_owner_id from public.tournaments where id = old.tournament_id;
  v_privileged := public.is_admin(auth.uid()) or (v_owner_id = auth.uid());

  if not v_privileged then
    select user_id into v_player1_user from public.tournament_players where id = old.player1_id;
    select user_id into v_player2_user from public.tournament_players where id = old.player2_id;

    v_is_p1_reporter := v_player1_user is not null and v_player1_user = auth.uid();
    v_is_p2_reporter := v_player2_user is not null and v_player2_user = auth.uid();

    -- Not the owner/admin: revert everything except the caller's own
    -- report columns. status is intentionally included here (a
    -- self-reporter cannot set it directly) — it gets recomputed, if
    -- applicable, by the auto-confirmation block below.
    new.tournament_id := old.tournament_id;
    new.round_key := old.round_key;
    new.player1_id := old.player1_id;
    new.player2_id := old.player2_id;
    new.score1 := old.score1;
    new.score2 := old.score2;
    new.winner_id := old.winner_id;
    new.status := old.status;
    new.created_at := old.created_at;

    if not v_is_p1_reporter then
      new.player1_reported_score := old.player1_reported_score;
      new.player1_reported_at := old.player1_reported_at;
    end if;

    if not v_is_p2_reporter then
      new.player2_reported_score := old.player2_reported_score;
      new.player2_reported_at := old.player2_reported_at;
    end if;

    -- A caller who is neither a recognised self-reporter for this match
    -- nor the owner/admin ends up with every column reverted to OLD, i.e.
    -- a no-op update. RLS should already have blocked this update from
    -- reaching here at all; this is defense in depth only.
  end if;

  -- Auto-confirmation reacts only to the *reported* columns actually
  -- changing, regardless of who changed them, so an owner directly
  -- overriding score1/score2/winner_id/status (their existing prompt-3
  -- path) is never touched by this block.
  if new.player1_reported_score is distinct from old.player1_reported_score
     or new.player2_reported_score is distinct from old.player2_reported_score then

    if new.player1_reported_score is not null and new.player2_reported_score is not null then
      if new.player1_reported_score = new.player2_reported_score then
        -- Both sides have reported but the tallies are tied, which is an
        -- ambiguous/anomalous outcome for a decisive match (no derivable
        -- winner) -- flag for the organizer instead of guessing. Leave
        -- score1/score2/winner_id untouched, per spec.
        new.status := 'disputed';
      else
        new.score1 := new.player1_reported_score;
        new.score2 := new.player2_reported_score;
        new.winner_id := case
          when new.player1_reported_score > new.player2_reported_score then new.player1_id
          else new.player2_id
        end;
        new.status := 'completed';
      end if;
    end if;
    -- Only one side has reported so far: leave status as pending/live,
    -- nothing else to do yet.
  end if;

  return new;
end;
$$;

comment on function public.handle_match_self_report() is
  'BEFORE UPDATE on matches: restricts non-owner/non-admin callers to only their own reporting columns, then auto-fills score1/score2/winner_id/status=completed once both sides have reported a decisive (non-tied) result, or status=disputed on a tied double-report. Owner/admin direct edits to score1/score2/winner_id/status are never touched by this trigger.';

create trigger matches_handle_self_report
  before update on public.matches
  for each row execute function public.handle_match_self_report();

-- ----------------------------------------------------------------------------
-- 5. INDEXES
-- ----------------------------------------------------------------------------
create index if not exists matches_player1_id_idx on public.matches (player1_id);
create index if not exists matches_player2_id_idx on public.matches (player2_id);

-- ----------------------------------------------------------------------------
-- 6. RLS — PLAYER SELF-REPORT POLICY
-- ----------------------------------------------------------------------------
-- Alongside prompt 3's existing matches_update_owner policy (not removed).
-- Row-level: allows an update if the caller is linked (via
-- tournament_players.user_id) to either participant slot on this match.
-- Column-level restriction (only their own report columns are actually
-- writable) is enforced by the trigger above, not by this policy.
create policy matches_self_report
  on public.matches
  for update
  to authenticated
  using (
    exists (
      select 1 from public.tournament_players tp
      where tp.id = matches.player1_id and tp.user_id = auth.uid()
    )
    or exists (
      select 1 from public.tournament_players tp
      where tp.id = matches.player2_id and tp.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.tournament_players tp
      where tp.id = matches.player1_id and tp.user_id = auth.uid()
    )
    or exists (
      select 1 from public.tournament_players tp
      where tp.id = matches.player2_id and tp.user_id = auth.uid()
    )
  );

-- No grant changes needed: `grant ... update on public.matches to
-- authenticated` already exists from 0003 and covers this new policy too.
