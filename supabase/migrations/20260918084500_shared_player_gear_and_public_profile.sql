-- Shared player gear for PRO and PRO+; public player profile available for all player plans.

drop policy if exists player_gear_owner_select on public.player_gear;
create policy player_gear_owner_select
on public.player_gear for select to authenticated
using (
  (select auth.uid()) = user_id
  and public.has_plan_at_least((select auth.uid()), 'pro')
);

drop policy if exists player_gear_owner_insert on public.player_gear;
create policy player_gear_owner_insert
on public.player_gear for insert to authenticated
with check (
  (select auth.uid()) = user_id
  and public.has_plan_at_least((select auth.uid()), 'pro')
);

drop policy if exists player_gear_owner_update on public.player_gear;
create policy player_gear_owner_update
on public.player_gear for update to authenticated
using (
  (select auth.uid()) = user_id
  and public.has_plan_at_least((select auth.uid()), 'pro')
)
with check (
  (select auth.uid()) = user_id
  and public.has_plan_at_least((select auth.uid()), 'pro')
);

grant select, insert, update on table public.player_gear to authenticated;

create or replace function public.get_my_player_gear()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.player_gear;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if not public.has_plan_at_least(v_uid, 'pro') then
    return jsonb_build_object('board_name',null,'equipment_name',null,'motto',null,'locked',true);
  end if;

  select * into v_row from public.player_gear where user_id=v_uid;

  return jsonb_build_object(
    'board_name',v_row.board_name,
    'equipment_name',v_row.equipment_name,
    'motto',v_row.motto,
    'locked',false
  );
end;
$$;

revoke all on function public.get_my_player_gear() from public, anon;
grant execute on function public.get_my_player_gear() to authenticated, service_role;

create or replace function public.update_my_player_gear(
  p_board_name text,
  p_equipment_name text,
  p_motto text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.player_gear;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if not public.has_plan_at_least(v_uid, 'pro') then
    raise exception 'PRO plan required' using errcode = '42501';
  end if;
  if char_length(coalesce(p_board_name,'')) > 120
     or char_length(coalesce(p_equipment_name,'')) > 120
     or char_length(coalesce(p_motto,'')) > 240 then
    raise exception 'gear value is too long' using errcode = '22001';
  end if;

  insert into public.player_gear(user_id,board_name,equipment_name,motto,updated_at)
  values (
    v_uid,
    nullif(btrim(p_board_name),''),
    nullif(btrim(p_equipment_name),''),
    nullif(btrim(p_motto),''),
    now()
  )
  on conflict (user_id) do update set
    board_name=excluded.board_name,
    equipment_name=excluded.equipment_name,
    motto=excluded.motto,
    updated_at=now()
  returning * into v_row;

  return jsonb_build_object(
    'board_name',v_row.board_name,
    'equipment_name',v_row.equipment_name,
    'motto',v_row.motto
  );
end;
$$;

revoke all on function public.update_my_player_gear(text,text,text) from public, anon;
grant execute on function public.update_my_player_gear(text,text,text) to authenticated, service_role;

create or replace function profile_private.get_public_pro_plus_profile_core(p_player_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $$
declare
  v_profile jsonb;
  v_plan text;
  v_disciplines jsonb;
  v_summary jsonb;
  v_achievements jsonb;
  v_challenges jsonb;
  v_gear jsonb;
  v_trainings jsonb;
  v_matches jsonb;
begin
  if p_player_id is null then
    raise exception 'player id required' using errcode = '22023';
  end if;

  select public.current_plan(p.id)::text,
         jsonb_build_object(
           'id',p.id,'full_name',p.full_name,'role',p.role::text,
           'plan',public.current_plan(p.id)::text,'avatar_url',p.avatar_url,
           'bio',p.bio,'city',p.city,'country_code',p.country_code,
           'created_at',p.created_at
         )
  into v_plan,v_profile
  from public.profiles p
  where p.id=p_player_id and p.role::text='player';

  if v_profile is null then
    return null;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',pd.id,'sport',pd.sport,'discipline',pd.discipline,'is_primary',pd.is_primary
  ) order by pd.is_primary desc,pd.created_at),'[]'::jsonb)
  into v_disciplines
  from public.player_disciplines pd
  where pd.player_id=p_player_id;

  with official as (
    select (m.winner_id=tp.id) as won
    from public.tournament_players tp
    join public.matches m on m.player1_id=tp.id or m.player2_id=tp.id
    where tp.user_id=p_player_id and m.status in ('completed','forfeited') and m.winner_id is not null
    union all
    select (lm.winner_id=lp.id) as won
    from public.league_players lp
    join public.league_matches lm on lm.player1_id=lp.id or lm.player2_id=lp.id
    where lp.user_id=p_player_id and lm.status in ('completed','forfeited') and lm.winner_id is not null
  )
  select jsonb_build_object(
    'matches_completed',count(*)::integer,
    'wins',count(*) filter(where won)::integer,
    'losses',count(*) filter(where not won)::integer,
    'win_rate',case when count(*)=0 then 0 else round(count(*) filter(where won)::numeric*100/count(*),1) end
  ) into v_summary from official;

  select jsonb_build_object(
    'summary',jsonb_build_object(
      'points',coalesce(sum(d.points) filter(where pa.user_id is not null),0),
      'unlocked',count(*) filter(where pa.user_id is not null),
      'total',count(*)
    ),
    'items',coalesce(jsonb_agg(jsonb_build_object(
      'code',d.code,'name',d.name,'points',d.points,'rarity',d.rarity,
      'current_value',coalesce(ap.current_value,0),'target_value',d.target_value,
      'unlocked',(pa.user_id is not null),'unlocked_at',pa.unlocked_at
    ) order by (pa.user_id is not null) desc,d.sort_order),'[]'::jsonb)
  ) into v_achievements
  from public.achievement_definitions d
  left join public.player_achievement_progress ap on ap.achievement_code=d.code and ap.user_id=p_player_id
  left join public.player_achievements pa on pa.achievement_code=d.code and pa.user_id=p_player_id
  where d.active;

  with season as (
    select s.* from public.challenge_seasons s
    where s.active and now() between s.starts_at and s.ends_at
    order by s.season_year desc limit 1
  ), joined as (
    select c.id,c.code,c.title,c.medal,c.badge_symbol,c.target_value,c.unit_label,
           pc.progress_value,pc.joined_at,pc.completed_at,
           case when pc.completed_at is not null then 'completed' else 'joined' end as state
    from season s
    join public.challenges c on c.season_id=s.id and c.active
    join public.player_challenges pc on pc.challenge_id=c.id and pc.user_id=p_player_id
  )
  select jsonb_build_object(
    'season',coalesce((select jsonb_build_object('year',s.season_year,'name',s.name) from season s),'{}'::jsonb),
    'summary',jsonb_build_object(
      'total',coalesce((select count(*) from public.challenges c join season s on s.id=c.season_id where c.active),0),
      'completed',coalesce((select count(*) from joined where completed_at is not null),0),
      'active',coalesce((select count(*) from joined where completed_at is null),0)
    ),
    'items',coalesce((select jsonb_agg(to_jsonb(x) order by (x.completed_at is null) desc,x.joined_at desc) from joined x),'[]'::jsonb)
  ) into v_challenges;

  select jsonb_build_object('board_name',g.board_name,'equipment_name',g.equipment_name,'motto',g.motto)
  into v_gear from public.player_gear g where g.user_id=p_player_id;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.occurred_at desc),'[]'::jsonb)
  into v_trainings
  from (
    select ts.id,ts.sport,ts.discipline,
           coalesce(ts.completed_at,ts.archived_at,ts.played_at,ts.updated_at,ts.created_at) as occurred_at
    from public.training_sessions ts
    where (ts.owner_id=p_player_id or exists(
      select 1 from public.training_session_participants tsp
      where tsp.training_session_id=ts.id and tsp.player_id=p_player_id
    )) and ts.status in ('completed','archived')
    order by occurred_at desc limit 4
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.occurred_at desc),'[]'::jsonb)
  into v_matches
  from (
    select m.id,t.sport,t.discipline,t.name as tournament_name,opponent.name as opponent_name,
           case when m.player1_id=mine.id then m.score1 else m.score2 end as my_score,
           case when m.player1_id=mine.id then m.score2 else m.score1 end as opponent_score,
           case when m.winner_id=mine.id then 'win' else 'loss' end as result,
           coalesce(m.completed_at,m.updated_at,m.created_at) as occurred_at
    from public.tournament_players mine
    join public.matches m on m.player1_id=mine.id or m.player2_id=mine.id
    join public.tournaments t on t.id=m.tournament_id
    left join public.tournament_players opponent on opponent.id=case when m.player1_id=mine.id then m.player2_id else m.player1_id end
    where mine.user_id=p_player_id and m.status in ('completed','forfeited') and m.winner_id is not null
    order by occurred_at desc limit 4
  ) x;

  return jsonb_build_object(
    'profile',v_profile,
    'disciplines',coalesce(v_disciplines,'[]'::jsonb),
    'summary',coalesce(v_summary,'{}'::jsonb),
    'achievements',coalesce(v_achievements,'{}'::jsonb),
    'challenges',coalesce(v_challenges,'{}'::jsonb),
    'gear',coalesce(v_gear,jsonb_build_object('board_name',null,'equipment_name',null,'motto',null)),
    'recent_trainings',coalesce(v_trainings,'[]'::jsonb),
    'recent_matches',coalesce(v_matches,'[]'::jsonb)
  );
end;
$$;
