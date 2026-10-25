-- Teams scoreboard integration.
-- Allows authenticated PRO+/ULTRA owners to load, live-sync and complete a team duel.

create or replace function public.get_team_scoreboard_game(p_game_id uuid)
returns table(
  game_id uuid,meeting_id uuid,competition_id uuid,competition_name text,sport text,
  discipline text,race_to integer,slot_no integer,game_status text,home_score integer,away_score integer,
  home_member_id uuid,away_member_id uuid,home_player_name text,away_player_name text,
  home_user_id uuid,away_user_id uuid,home_team_name text,away_team_name text
)
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.can_use_teams() then raise exception 'Teams requires PRO+ or ULTRA'; end if;
  return query
  select g.id,g.meeting_id,c.id,c.name,c.sport,g.discipline,g.race_to,g.slot_no,g.status,
         g.home_score,g.away_score,g.home_member_id,g.away_member_id,
         hm.display_name,am.display_name,hm.user_id,am.user_id,ht.name,at.name
  from public.team_match_games g
  join public.team_meetings m on m.id=g.meeting_id
  join public.team_competitions c on c.id=m.competition_id
  join public.teams ht on ht.id=m.home_team_id
  join public.teams at on at.id=m.away_team_id
  left join public.team_members hm on hm.id=g.home_member_id
  left join public.team_members am on am.id=g.away_member_id
  where g.id=p_game_id and c.owner_id=auth.uid();
  if not found then raise exception 'Team duel not found or access denied'; end if;
end;
$$;

create or replace function public.update_team_scoreboard_live(p_game_id uuid,p_home_score integer,p_away_score integer)
returns public.team_match_games
language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.team_match_games;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.can_use_teams() then raise exception 'Teams requires PRO+ or ULTRA'; end if;
  if p_home_score<0 or p_away_score<0 then raise exception 'Invalid score'; end if;
  update public.team_match_games g
  set home_score=p_home_score,away_score=p_away_score,
      status=case when g.status='scheduled' then 'active' else g.status end,updated_at=now()
  from public.team_meetings m join public.team_competitions c on c.id=m.competition_id
  where g.id=p_game_id and m.id=g.meeting_id and c.owner_id=auth.uid() and g.status not in ('completed','cancelled')
  returning g.* into v;
  if v.id is null then raise exception 'Team duel not found, closed, or access denied'; end if;
  return v;
end;
$$;

create or replace function public.complete_team_scoreboard_game(p_game_id uuid,p_home_score integer,p_away_score integer)
returns public.team_match_games
language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.team_match_games;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.can_use_teams() then raise exception 'Teams requires PRO+ or ULTRA'; end if;
  if p_home_score<0 or p_away_score<0 or p_home_score=p_away_score then raise exception 'Invalid final score'; end if;
  update public.team_match_games g
  set home_score=p_home_score,away_score=p_away_score,status='completed',updated_at=now()
  from public.team_meetings m join public.team_competitions c on c.id=m.competition_id
  where g.id=p_game_id and m.id=g.meeting_id and c.owner_id=auth.uid() and g.status<>'cancelled'
  returning g.* into v;
  if v.id is null then raise exception 'Team duel not found or access denied'; end if;
  return v;
end;
$$;

revoke all on function public.get_team_scoreboard_game(uuid) from public,anon;
revoke all on function public.update_team_scoreboard_live(uuid,integer,integer) from public,anon;
revoke all on function public.complete_team_scoreboard_game(uuid,integer,integer) from public,anon;
grant execute on function public.get_team_scoreboard_game(uuid) to authenticated;
grant execute on function public.update_team_scoreboard_live(uuid,integer,integer) to authenticated;
grant execute on function public.complete_team_scoreboard_game(uuid,integer,integer) to authenticated;
