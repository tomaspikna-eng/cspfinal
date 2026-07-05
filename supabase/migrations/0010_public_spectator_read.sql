-- ============================================================================
-- CSP Database — Migration 0010: Public Spectator Layer
-- (Clubs, Venues, Tournaments)
-- ============================================================================
-- Architecture principle: throughout CSP there are always two layers —
-- anyone, including a logged-out visitor, can BROWSE/SPECTATE public
-- content (find a club, see what it offers, watch a tournament's live
-- progress), but only the actual owner/organizer can WRITE/MANAGE it.
-- This migration is purely additive read access to bring `tournaments`
-- (+ its children) and `clubs`/`venues` in line with that principle.
-- No write/INSERT/UPDATE/DELETE policy anywhere is touched.
--
-- `stations` (migration 0005) is DELIBERATELY NOT touched here. Its
-- lack of a public SELECT policy is a security design, not an
-- oversight: individual QR-linked scoreboards must never be listable by
-- anyone (owner or anon), only reachable one-at-a-time via
-- get_station_by_token() with an exact, unguessable token. That's an
-- unrelated concern to club-browsing/spectating and stays exactly as
-- migration 0005 left it.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. CLEAN SLATE
-- ----------------------------------------------------------------------------
-- All tables involved already exist by the time this migration runs
-- (0003, 0005, 0009), so unlike 0001's fresh-project caveat, dropping
-- these policies by name is always safe here.
drop policy if exists tournaments_select_published on public.tournaments;
drop policy if exists tournament_players_select on public.tournament_players;
drop policy if exists tournament_groups_select on public.tournament_groups;
drop policy if exists matches_select on public.matches;
drop policy if exists clubs_select_public on public.clubs;
drop policy if exists venues_select_public on public.venues;

-- ----------------------------------------------------------------------------
-- 1. TOURNAMENTS (+ players, groups, matches) — extend to anon
-- ----------------------------------------------------------------------------
-- Same USING logic as migration 0003, just widened from `authenticated`
-- only to `anon, authenticated` — a logged-out visitor should be able to
-- open a published tournament, see the bracket/standings, and watch
-- match scores update live, but (per the existing owner-only write
-- policies, untouched) never write anything.
create policy tournaments_select_published
  on public.tournaments
  for select
  to anon, authenticated
  using (status <> 'draft');

grant select on public.tournaments to anon;

create policy tournament_players_select
  on public.tournament_players
  for select
  to anon, authenticated
  using (
    exists (
      select 1 from public.tournaments t
      where t.id = tournament_players.tournament_id
        and (t.owner_id = auth.uid() or t.status <> 'draft')
    )
  );

grant select on public.tournament_players to anon;

create policy tournament_groups_select
  on public.tournament_groups
  for select
  to anon, authenticated
  using (
    exists (
      select 1 from public.tournaments t
      where t.id = tournament_groups.tournament_id
        and (t.owner_id = auth.uid() or t.status <> 'draft')
    )
  );

grant select on public.tournament_groups to anon;

create policy matches_select
  on public.matches
  for select
  to anon, authenticated
  using (
    exists (
      select 1 from public.tournaments t
      where t.id = matches.tournament_id
        and (t.owner_id = auth.uid() or t.status <> 'draft')
    )
  );

grant select on public.matches to anon;

-- Note: `t.owner_id = auth.uid()` in the child-table policies above is
-- simply never true for the anon role (auth.uid() is null with no
-- session), so anon falls through to the `t.status <> 'draft'` check —
-- exactly the intended "published only" visibility, same as
-- authenticated non-owners already had.

-- ----------------------------------------------------------------------------
-- 2. CLUBS — add public read (foundation for a future club directory)
-- ----------------------------------------------------------------------------
-- Deferred in migration 0005 ("may change later if/when a public club
-- directory is designed") — that directory is being designed now. A
-- club's name and existence are meant to be publicly discoverable.
-- Owner-only write (clubs_owner_all, migration 0005) is unchanged.
create policy clubs_select_public
  on public.clubs
  for select
  to anon, authenticated
  using (true);

grant select on public.clubs to anon;

-- ----------------------------------------------------------------------------
-- 3. VENUES — add public read
-- ----------------------------------------------------------------------------
-- Same reasoning as clubs: anyone should be able to see what
-- facilities/courts a club offers before deciding to visit or register.
-- Owner-only write (venues_owner_all, migration 0009) is unchanged.
create policy venues_select_public
  on public.venues
  for select
  to anon, authenticated
  using (true);

grant select on public.venues to anon;

-- ----------------------------------------------------------------------------
-- 4. stations — explicitly confirmed untouched (see header comment)
-- ----------------------------------------------------------------------------
-- No statement in this migration references public.stations at all.
-- It keeps its migration-0005 access model: owner-only CRUD, plus the
-- anonymous get_station_by_token() function for exact-token lookups —
-- never a listable/enumerable SELECT for anon or authenticated.
