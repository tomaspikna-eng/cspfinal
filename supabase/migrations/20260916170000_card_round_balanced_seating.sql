-- Balanced card rounds with a per-round preferred table size.
-- The greedy seating pass minimizes repeated opponents while preserving
-- table sizes that differ by at most one player.

create or replace function public.advance_card_round_configured(
  p_tournament_id uuid,
  p_players_per_table integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_settings public.card_tournament_settings%rowtype;
  v_current_round public.card_rounds%rowtype;
  v_next_round_id uuid;
  v_survivor_count integer;
  v_preferred integer;
  v_table_count integer;
  v_base_size integer;
  v_extra_tables integer;
  v_next_number integer;
  v_player record;
  v_table_number integer;
begin
  if (select auth.uid()) is null then
    raise exception 'AUTHENTICATION_REQUIRED';
  end if;

  select s.* into v_settings
  from public.card_tournament_settings s
  join public.tournaments t on t.id=s.tournament_id
  where s.tournament_id=p_tournament_id
    and (t.owner_id=(select auth.uid()) or coalesce(public.is_admin((select auth.uid())),false))
  for update of s;

  if v_settings.tournament_id is null then raise exception 'CARD_TOURNAMENT_NOT_FOUND_OR_FORBIDDEN'; end if;
  if v_settings.status<>'in_progress' then raise exception 'CARD_TOURNAMENT_IS_NOT_RUNNING'; end if;

  v_preferred:=coalesce(p_players_per_table,v_settings.players_per_table);
  if v_preferred<2 or v_preferred>8 then raise exception 'PLAYERS_PER_TABLE_MUST_BE_2_TO_8'; end if;

  select * into v_current_round
  from public.card_rounds
  where tournament_id=p_tournament_id
    and round_number=v_settings.current_round_number
  for update;

  if v_current_round.id is null or v_current_round.round_type='final' then
    raise exception 'CARD_FINAL_ROUND_CANNOT_ADVANCE';
  end if;
  if exists(
    select 1 from public.card_tables
    where round_id=v_current_round.id and status<>'completed'
  ) then
    raise exception 'ALL_CARD_TABLES_MUST_BE_COMPLETED';
  end if;

  select count(*)::integer into v_survivor_count
  from public.card_table_players
  where round_id=v_current_round.id and outcome='active';

  if v_survivor_count<v_settings.final_player_count then raise exception 'TOO_FEW_PLAYERS_FOR_FINAL'; end if;
  if v_survivor_count=(
    select count(*) from public.card_table_players where round_id=v_current_round.id
  ) then
    raise exception 'AT_LEAST_ONE_PLAYER_MUST_BE_ELIMINATED';
  end if;

  v_next_number:=v_current_round.round_number+1;
  v_table_count:=case
    when v_survivor_count=v_settings.final_player_count then 1
    else public.card_fair_table_count(v_survivor_count,v_preferred,v_settings.final_player_count)
  end;
  v_base_size:=floor(v_survivor_count::numeric/v_table_count)::integer;
  v_extra_tables:=v_survivor_count%v_table_count;

  drop table if exists pg_temp.csp_card_round_assignments;
  create temporary table pg_temp.csp_card_round_assignments(
    player_id uuid primary key,
    table_number integer not null
  ) on commit drop;

  for v_player in
    select ctp.tournament_player_id as player_id
    from public.card_table_players ctp
    where ctp.round_id=v_current_round.id and ctp.outcome='active'
    order by pg_catalog.md5(ctp.tournament_player_id::text||':'||v_next_number::text||':'||p_tournament_id::text)
  loop
    select candidate.table_number into v_table_number
    from pg_catalog.generate_series(1,v_table_count) as candidate(table_number)
    where (
      select count(*) from pg_temp.csp_card_round_assignments assigned
      where assigned.table_number=candidate.table_number
    ) < v_base_size + case when candidate.table_number<=v_extra_tables then 1 else 0 end
    order by
      (
        select count(*)
        from public.card_table_players previous_player
        join public.card_rounds previous_round on previous_round.id=previous_player.round_id
        join public.card_table_players previous_opponent
          on previous_opponent.table_id=previous_player.table_id
         and previous_opponent.round_id=previous_player.round_id
        join pg_temp.csp_card_round_assignments assigned_opponent
          on assigned_opponent.player_id=previous_opponent.tournament_player_id
         and assigned_opponent.table_number=candidate.table_number
        where previous_round.tournament_id=p_tournament_id
          and previous_round.round_number<=v_current_round.round_number
          and previous_player.tournament_player_id=v_player.player_id
          and previous_opponent.tournament_player_id<>v_player.player_id
      ) asc,
      (
        select count(*) from pg_temp.csp_card_round_assignments assigned
        where assigned.table_number=candidate.table_number
      ) asc,
      pg_catalog.md5(v_player.player_id::text||':'||candidate.table_number::text||':'||v_next_number::text) asc
    limit 1;

    if v_table_number is null then raise exception 'CARD_TABLE_ASSIGNMENT_FAILED'; end if;
    insert into pg_temp.csp_card_round_assignments(player_id,table_number)
    values(v_player.player_id,v_table_number);
  end loop;

  update public.card_rounds
  set status='completed',completed_at=coalesce(completed_at,now())
  where id=v_current_round.id;

  insert into public.card_rounds(tournament_id,round_number,round_type,status)
  values(
    p_tournament_id,v_next_number,
    case when v_survivor_count=v_settings.final_player_count then 'final' else 'qualification' end,
    'open'
  ) returning id into v_next_round_id;

  insert into public.card_tables(round_id,table_number,label,status)
  select v_next_round_id,n,'Stôl '||n,'open'
  from pg_catalog.generate_series(1,v_table_count) n;

  insert into public.card_table_players(table_id,round_id,tournament_player_id,seat_number)
  select
    ct.id,
    v_next_round_id,
    assignment.player_id,
    row_number() over(
      partition by assignment.table_number
      order by pg_catalog.md5(assignment.player_id::text||':'||v_next_number::text)
    )::smallint
  from pg_temp.csp_card_round_assignments assignment
  join public.card_tables ct
    on ct.round_id=v_next_round_id
   and ct.table_number=assignment.table_number;

  update public.card_tournament_settings
  set current_round_number=v_next_number,
      players_per_table=v_preferred
  where tournament_id=p_tournament_id;

  return public.get_card_tournament_state(p_tournament_id);
end;
$$;

revoke all on function public.advance_card_round_configured(uuid,integer) from public,anon;
grant execute on function public.advance_card_round_configured(uuid,integer) to authenticated,service_role;

