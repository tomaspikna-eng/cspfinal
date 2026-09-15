-- Connect Sports Pro — Global Core Series 01 (beta v2)
-- Universal achievements across supported sports.

update public.achievement_definitions set active=false, updated_at=now()
where code in ('active_weeks_4','active_weeks_12','active_weeks_26');

update public.achievement_definitions set
  name = case code
    when 'first_win' then 'Prvá výhra'
    when 'first_tournament' then 'Turnajový debut'
    when 'wins_5' then 'Päť víťazstiev'
    when 'wins_10' then 'Desať víťazstiev'
    when 'win_streak_5' then 'Víťazná séria'
    when 'top_8' then 'TOP 8'
    when 'champion_2' then 'Dvojnásobný šampión'
    when 'champion_5' then 'Päťnásobný šampión'
    else name end,
  description = case code
    when 'first_win' then 'Vyhraj prvý oficiálny zápas.'
    when 'first_tournament' then 'Odohraj prvý turnaj v CSP.'
    when 'wins_5' then 'Vyhraj 5 oficiálnych zápasov.'
    when 'wins_10' then 'Vyhraj 10 oficiálnych zápasov.'
    when 'win_streak_5' then 'Vyhraj 5 oficiálnych zápasov za sebou.'
    when 'top_8' then 'Postúp medzi posledných 8 hráčov turnaja.'
    when 'semifinal' then 'Postúp do semifinále turnaja.'
    when 'finalist' then 'Postúp do finále turnaja.'
    when 'champion_2' then 'Vyhraj 2 turnaje.'
    when 'champion_5' then 'Vyhraj 5 turnajov.'
    else description end,
  sort_order = case code
    when 'top_8' then 18
    when 'semifinal' then 19
    when 'finalist' then 20
    when 'champion' then 21
    when 'champion_2' then 23
    when 'champion_5' then 24
    else sort_order end,
  updated_at=now()
where code in ('first_win','first_tournament','wins_5','wins_10','win_streak_5','top_8','semifinal','finalist','champion','champion_2','champion_5');

insert into public.achievement_definitions
(code,series_code,name,description,category,metric,target_value,points,rarity,sort_order,active,auto_award,created_at,updated_at)
values
('group_winner','core_01','Víťaz skupiny','Vyhraj skupinu v dvojfázovom turnaji.','vykon','group_wins',1,15,'silver',17,true,true,now(),now()),
('clean_tournament','core_01','Čistý turnaj','Vyhraj turnaj bez jedinej prehry.','vynimocne','clean_tournament_wins',1,40,'platinum',22,true,true,now(),now()),
('tournaments_10','core_01','Veterán CSP','Odohraj 10 turnajov v CSP.','progres','tournaments_played',10,30,'gold',25,true,true,now(),now())
on conflict(code) do update set
series_code=excluded.series_code,name=excluded.name,description=excluded.description,category=excluded.category,metric=excluded.metric,
target_value=excluded.target_value,points=excluded.points,rarity=excluded.rarity,sort_order=excluded.sort_order,active=true,auto_award=true,updated_at=now();

create or replace function public.refresh_player_achievements(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare
  v_profile_complete integer := 0;
  v_matches integer := 0;
  v_wins integer := 0;
  v_training integer := 0;
  v_tournaments integer := 0;
  v_tournament_wins integer := 0;
  v_top8 integer := 0;
  v_semifinal integer := 0;
  v_final integer := 0;
  v_group_wins integer := 0;
  v_clean_tournament_wins integer := 0;
  v_longest_win_streak integer := 0;
  v_current_win_streak integer := 0;
  v_won boolean;
begin
  if p_user_id is null or not exists (select 1 from public.profiles p where p.id=p_user_id) then return; end if;

  select case when nullif(btrim(coalesce(p.full_name,'')),'') is not null
                    and nullif(btrim(coalesce(p.avatar_url,'')),'') is not null
                    and nullif(btrim(coalesce(p.bio,'')),'') is not null
                    and exists(select 1 from public.player_disciplines pd where pd.player_id=p.id)
              then 1 else 0 end
    into v_profile_complete
  from public.profiles p where p.id=p_user_id;

  with official as (
    select m.id, coalesce(m.completed_at,m.updated_at,m.created_at) as occurred_at,
           (m.winner_id=tp.id) as won
    from public.tournament_players tp
    join public.matches m on m.player1_id=tp.id or m.player2_id=tp.id
    where tp.user_id=p_user_id and m.status in ('completed','forfeited') and m.winner_id is not null
    union all
    select lm.id, coalesce(lm.completed_at,lm.updated_at,lm.created_at) as occurred_at,
           (lm.winner_id=lp.id) as won
    from public.league_players lp
    join public.league_matches lm on lm.player1_id=lp.id or lm.player2_id=lp.id
    where lp.user_id=p_user_id and lm.status in ('completed','forfeited') and lm.winner_id is not null
  )
  select count(*)::int, count(*) filter(where won)::int into v_matches,v_wins from official;

  for v_won in
    select x.won from (
      select m.id::text as id, coalesce(m.completed_at,m.updated_at,m.created_at) as occurred_at, (m.winner_id=tp.id) as won
      from public.tournament_players tp join public.matches m on m.player1_id=tp.id or m.player2_id=tp.id
      where tp.user_id=p_user_id and m.status in ('completed','forfeited') and m.winner_id is not null
      union all
      select lm.id::text, coalesce(lm.completed_at,lm.updated_at,lm.created_at), (lm.winner_id=lp.id)
      from public.league_players lp join public.league_matches lm on lm.player1_id=lp.id or lm.player2_id=lp.id
      where lp.user_id=p_user_id and lm.status in ('completed','forfeited') and lm.winner_id is not null
    ) x order by x.occurred_at,x.id
  loop
    if v_won then
      v_current_win_streak:=v_current_win_streak+1;
      v_longest_win_streak:=greatest(v_longest_win_streak,v_current_win_streak);
    else
      v_current_win_streak:=0;
    end if;
  end loop;

  select count(*)::int into v_training
  from public.training_sessions ts
  where ts.status in ('completed','archived')
    and (ts.owner_id=p_user_id or exists(select 1 from public.training_session_participants tsp where tsp.training_session_id=ts.id and tsp.player_id=p_user_id));

  select count(*)::int into v_tournaments from (
    select distinct m.tournament_id
    from public.tournament_players tp join public.matches m on m.player1_id=tp.id or m.player2_id=tp.id
    where tp.user_id=p_user_id and m.status in ('completed','forfeited')
    union
    select distinct tr.tournament_id from public.tournament_results tr where tr.user_id=p_user_id
  ) q;

  select count(*) filter(where tr.final_position=1)::int,
         count(*) filter(where tr.final_position between 1 and 8)::int,
         count(*) filter(where tr.final_position between 1 and 4)::int,
         count(*) filter(where tr.final_position between 1 and 2)::int
    into v_tournament_wins,v_top8,v_semifinal,v_final
  from public.tournament_results tr where tr.user_id=p_user_id;

  select count(distinct pq.phase_id)::int into v_group_wins
  from public.phase_qualifiers pq
  join public.tournament_players tp on tp.id=pq.tournament_player_id
  join public.tournament_phases ph on ph.id=pq.phase_id
  where tp.user_id=p_user_id
    and ph.phase_type='RR'
    and nullif(pq.metadata->>'source_position','')::int=1
    and exists (
      select 1 from public.tournament_phases next_ph
      where next_ph.tournament_id=ph.tournament_id
        and next_ph.phase_number>ph.phase_number
        and next_ph.phase_type in ('SKO','DKO')
        and (next_ph.config->>'source_phase_id'=ph.id::text or next_ph.config->>'source_phase_id' is null)
    );

  select count(*)::int into v_clean_tournament_wins
  from public.tournament_results tr
  where tr.user_id=p_user_id and tr.final_position=1
    and exists (
      select 1
      from public.tournament_players tp
      join public.matches m on (m.player1_id=tp.id or m.player2_id=tp.id)
      where tp.user_id=p_user_id and tp.tournament_id=tr.tournament_id
        and m.tournament_id=tr.tournament_id
        and m.status in ('completed','forfeited')
        and m.winner_id=tp.id
    )
    and not exists (
      select 1
      from public.tournament_players tp
      join public.matches m on (m.player1_id=tp.id or m.player2_id=tp.id)
      where tp.user_id=p_user_id and tp.tournament_id=tr.tournament_id
        and m.tournament_id=tr.tournament_id
        and m.status in ('completed','forfeited')
        and m.winner_id is not null
        and m.winner_id<>tp.id
    );

  insert into public.player_achievement_progress(user_id,achievement_code,current_value,target_value,unlocked,updated_at)
  select p_user_id,d.code,
    case d.metric
      when 'profile_complete' then v_profile_complete
      when 'matches_played' then v_matches
      when 'wins' then v_wins
      when 'training_sessions' then v_training
      when 'tournaments_played' then v_tournaments
      when 'win_streak' then v_longest_win_streak
      when 'top8_finishes' then v_top8
      when 'semifinal_finishes' then v_semifinal
      when 'final_finishes' then v_final
      when 'tournament_wins' then v_tournament_wins
      when 'group_wins' then v_group_wins
      when 'clean_tournament_wins' then v_clean_tournament_wins
      else 0 end,
    d.target_value,
    (case d.metric
      when 'profile_complete' then v_profile_complete
      when 'matches_played' then v_matches
      when 'wins' then v_wins
      when 'training_sessions' then v_training
      when 'tournaments_played' then v_tournaments
      when 'win_streak' then v_longest_win_streak
      when 'top8_finishes' then v_top8
      when 'semifinal_finishes' then v_semifinal
      when 'final_finishes' then v_final
      when 'tournament_wins' then v_tournament_wins
      when 'group_wins' then v_group_wins
      when 'clean_tournament_wins' then v_clean_tournament_wins
      else 0 end) >= d.target_value,
    now()
  from public.achievement_definitions d where d.active and d.auto_award
  on conflict(user_id,achievement_code) do update set
    current_value=excluded.current_value,target_value=excluded.target_value,
    unlocked=public.player_achievement_progress.unlocked or excluded.unlocked,updated_at=now();

  insert into public.player_achievements(user_id,achievement_code,unlocked_at,source)
  select p.user_id,p.achievement_code,now(),'achievement_engine'
  from public.player_achievement_progress p
  join public.achievement_definitions d on d.code=p.achievement_code and d.active
  where p.user_id=p_user_id and p.unlocked
  on conflict(user_id,achievement_code) do nothing;
end;
$$;

create or replace function public.get_my_achievements()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid := auth.uid();
  payload jsonb;
begin
  if uid is null then raise exception 'authentication required'; end if;
  perform public.refresh_player_achievements(uid);
  select jsonb_build_object(
    'series',jsonb_build_object('code','core_01','name','Global Core Series 01'),
    'summary',jsonb_build_object(
      'points',coalesce((select sum(d.points) from public.player_achievements pa join public.achievement_definitions d on d.code=pa.achievement_code where pa.user_id=uid and d.active),0),
      'unlocked',coalesce((select count(*) from public.player_achievements pa join public.achievement_definitions d on d.code=pa.achievement_code where pa.user_id=uid and d.active),0),
      'total',coalesce((select count(*) from public.achievement_definitions d where d.active),0)
    ),
    'items',coalesce((select jsonb_agg(jsonb_build_object(
      'code',d.code,'name',d.name,'description',d.description,'category',d.category,'metric',d.metric,
      'current_value',coalesce(p.current_value,0),'target_value',d.target_value,'points',d.points,'rarity',d.rarity,
      'unlocked',coalesce(p.unlocked,false),'unlocked_at',pa.unlocked_at
    ) order by d.sort_order)
    from public.achievement_definitions d
    left join public.player_achievement_progress p on p.achievement_code=d.code and p.user_id=uid
    left join public.player_achievements pa on pa.achievement_code=d.code and pa.user_id=uid
    where d.active),'[]'::jsonb)
  ) into payload;
  return payload;
end;
$$;

create or replace function public.achievement_refresh_from_qualifier()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  uid uuid;
begin
  select tp.user_id into uid
  from public.tournament_players tp
  where tp.id=coalesce(new.tournament_player_id,old.tournament_player_id);
  if uid is not null then perform public.refresh_player_achievements(uid); end if;
  return coalesce(new,old);
end;
$$;

revoke all on function public.achievement_refresh_from_qualifier() from public, anon, authenticated;

drop trigger if exists achievement_refresh_phase_qualifier on public.phase_qualifiers;
create trigger achievement_refresh_phase_qualifier
after insert or update or delete on public.phase_qualifiers
for each row execute function public.achievement_refresh_from_qualifier();

do $$ declare uid uuid; begin
  for uid in select id from public.profiles loop
    perform public.refresh_player_achievements(uid);
  end loop;
end $$;
