alter table public.team_match_games
  add column if not exists game_type text not null default 'singles'
    check (game_type in ('singles','doubles')),
  add column if not exists home_member2_id uuid references public.team_members(id) on delete set null,
  add column if not exists away_member2_id uuid references public.team_members(id) on delete set null;

create or replace function public.sync_team_game_winner()
returns trigger language plpgsql set search_path = public, pg_temp as $$
declare m public.team_meetings;
begin
  select * into m from public.team_meetings where id=new.meeting_id;
  if m.id is null then raise exception 'Team meeting not found'; end if;

  if new.home_member_id is not null and not exists(select 1 from public.team_members tm where tm.id=new.home_member_id and tm.team_id=m.home_team_id) then raise exception 'Home player is not on the home team'; end if;
  if new.away_member_id is not null and not exists(select 1 from public.team_members tm where tm.id=new.away_member_id and tm.team_id=m.away_team_id) then raise exception 'Away player is not on the away team'; end if;
  if new.home_member2_id is not null and not exists(select 1 from public.team_members tm where tm.id=new.home_member2_id and tm.team_id=m.home_team_id) then raise exception 'Second home player is not on the home team'; end if;
  if new.away_member2_id is not null and not exists(select 1 from public.team_members tm where tm.id=new.away_member2_id and tm.team_id=m.away_team_id) then raise exception 'Second away player is not on the away team'; end if;

  if new.game_type='singles' then
    new.home_member2_id:=null;
    new.away_member2_id:=null;
  else
    if new.home_member_id is not null and new.home_member2_id=new.home_member_id then raise exception 'Home doubles players must be different'; end if;
    if new.away_member_id is not null and new.away_member2_id=new.away_member_id then raise exception 'Away doubles players must be different'; end if;
  end if;

  if new.status='completed' then
    if new.home_member_id is null or new.away_member_id is null then raise exception 'Completed duel requires both sides'; end if;
    if new.game_type='doubles' and (new.home_member2_id is null or new.away_member2_id is null) then raise exception 'Completed doubles duel requires two players on each side'; end if;
    if new.home_score=new.away_score then raise exception 'Completed duel cannot end in a draw'; end if;
    if greatest(new.home_score,new.away_score)<new.race_to then raise exception 'Winner must reach Race to %',new.race_to; end if;
    if new.home_score>new.away_score then
      new.winner_team_id:=m.home_team_id;
      new.winner_member_id:=case when new.game_type='singles' then new.home_member_id else null end;
    else
      new.winner_team_id:=m.away_team_id;
      new.winner_member_id:=case when new.game_type='singles' then new.away_member_id else null end;
    end if;
    new.completed_at:=coalesce(new.completed_at,now());
  else
    new.winner_team_id:=null;new.winner_member_id:=null;new.completed_at:=null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_team_game_winner on public.team_match_games;
create trigger trg_sync_team_game_winner
before insert or update of status,home_score,away_score,home_member_id,away_member_id,home_member2_id,away_member2_id,game_type
on public.team_match_games
for each row execute function public.sync_team_game_winner();

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
         case when g.game_type='doubles' then concat_ws(' / ',hm.display_name,hm2.display_name) else hm.display_name end,
         case when g.game_type='doubles' then concat_ws(' / ',am.display_name,am2.display_name) else am.display_name end,
         hm.user_id,am.user_id,ht.name,at.name
  from public.team_match_games g
  join public.team_meetings m on m.id=g.meeting_id
  join public.team_competitions c on c.id=m.competition_id
  join public.teams ht on ht.id=m.home_team_id
  join public.teams at on at.id=m.away_team_id
  left join public.team_members hm on hm.id=g.home_member_id
  left join public.team_members hm2 on hm2.id=g.home_member2_id
  left join public.team_members am on am.id=g.away_member_id
  left join public.team_members am2 on am2.id=g.away_member2_id
  where g.id=p_game_id and c.owner_id=auth.uid();
  if not found then raise exception 'Team duel not found or access denied'; end if;
end;
$$;

revoke all on function public.get_team_scoreboard_game(uuid) from public,anon;
grant execute on function public.get_team_scoreboard_game(uuid) to authenticated;
