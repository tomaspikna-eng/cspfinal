-- Keep one read policy per role on the new captain-owned records and prevent
-- direct station mutations outside the validated RPCs.

alter policy leagues_authenticated_read on public.leagues
using (
  ((visibility in ('public','unlisted') and status <> 'draft')
   or owner_id = (select auth.uid())
   or public.can_manage_league(id)
   or public.is_league_captain_for_league(id))
);
drop policy if exists leagues_team_captain_read on public.leagues;

drop policy if exists league_match_lineups_public_read on public.league_match_lineups;
drop policy if exists league_match_lineups_captain_read on public.league_match_lineups;
create policy league_match_lineups_anon_read
on public.league_match_lineups for select to anon
using (
  exists (
    select 1 from public.league_matches m join public.leagues l on l.id=m.league_id
    where m.id=league_match_lineups.match_id
      and l.visibility in ('public','unlisted') and l.status<>'draft'
  )
);
create policy league_match_lineups_authenticated_read
on public.league_match_lineups for select to authenticated
using (
  exists (
    select 1 from public.league_matches m join public.leagues l on l.id=m.league_id
    where m.id=league_match_lineups.match_id
      and ((l.visibility in ('public','unlisted') and l.status<>'draft') or public.can_manage_league(l.id))
  )
  or public.league_captain_match_side(match_id) is not null
);

drop policy if exists league_match_sheets_public_read on public.league_match_sheets;
drop policy if exists league_match_sheets_captain_read on public.league_match_sheets;
create policy league_match_sheets_anon_read
on public.league_match_sheets for select to anon
using (
  exists (
    select 1 from public.league_matches m join public.leagues l on l.id=m.league_id
    where m.id=league_match_sheets.match_id
      and l.visibility in ('public','unlisted') and l.status<>'draft'
  )
);
create policy league_match_sheets_authenticated_read
on public.league_match_sheets for select to authenticated
using (
  exists (
    select 1 from public.league_matches m join public.leagues l on l.id=m.league_id
    where m.id=league_match_sheets.match_id
      and ((l.visibility in ('public','unlisted') and l.status<>'draft') or public.can_manage_league(l.id))
  )
  or public.league_captain_match_side(match_id) is not null
);

drop policy if exists league_resources_manager_all on public.league_resources;
drop policy if exists league_resources_captain_read on public.league_resources;
create policy league_resources_authenticated_read
on public.league_resources for select to authenticated
using (
  public.can_manage_league(league_id)
  or public.is_league_captain_for_league(league_id)
);

revoke insert,update,delete on public.league_resources from authenticated;
