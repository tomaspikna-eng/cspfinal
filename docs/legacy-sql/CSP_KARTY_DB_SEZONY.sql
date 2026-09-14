begin;

-- CSP card tournaments v1
-- Durable rounds/tables, projector payload, final results and card-season scoring.

create table if not exists public.card_tournament_settings (
  tournament_id uuid primary key references public.tournaments(id) on delete cascade,
  players_per_table smallint not null default 4 check (players_per_table between 2 and 8),
  final_player_count smallint not null default 4 check (final_player_count between 2 and 8),
  current_round_number integer not null default 0 check (current_round_number >= 0),
  status text not null default 'setup' check (status in ('setup','in_progress','completed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.card_rounds (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  round_number integer not null check (round_number > 0),
  round_type text not null default 'qualification' check (round_type in ('qualification','final')),
  status text not null default 'open' check (status in ('open','completed')),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (tournament_id, round_number)
);

create table if not exists public.card_tables (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references public.card_rounds(id) on delete cascade,
  table_number integer not null check (table_number > 0),
  label text not null,
  status text not null default 'open' check (status in ('open','completed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (round_id, table_number)
);

create table if not exists public.card_table_players (
  table_id uuid not null references public.card_tables(id) on delete cascade,
  round_id uuid not null references public.card_rounds(id) on delete cascade,
  tournament_player_id uuid not null references public.tournament_players(id) on delete cascade,
  seat_number smallint not null check (seat_number > 0),
  outcome text not null default 'active' check (outcome in ('active','eliminated','placed')),
  final_position integer check (final_position is null or final_position > 0),
  updated_at timestamptz not null default now(),
  primary key (table_id, tournament_player_id),
  unique (round_id, tournament_player_id),
  unique (table_id, seat_number)
);

create index if not exists card_rounds_tournament_current_idx
  on public.card_rounds (tournament_id, round_number desc);
create index if not exists card_tables_round_status_idx
  on public.card_tables (round_id, status, table_number);
create index if not exists card_table_players_round_outcome_idx
  on public.card_table_players (round_id, outcome, tournament_player_id);
create index if not exists card_table_players_player_idx
  on public.card_table_players (tournament_player_id, round_id);

drop trigger if exists card_tournament_settings_set_updated_at on public.card_tournament_settings;
create trigger card_tournament_settings_set_updated_at
before update on public.card_tournament_settings
for each row execute function public.set_updated_at();

drop trigger if exists card_tables_set_updated_at on public.card_tables;
create trigger card_tables_set_updated_at
before update on public.card_tables
for each row execute function public.set_updated_at();

alter table public.card_tournament_settings enable row level security;
alter table public.card_rounds enable row level security;
alter table public.card_tables enable row level security;
alter table public.card_table_players enable row level security;

drop policy if exists card_tournament_settings_read on public.card_tournament_settings;
create policy card_tournament_settings_read
on public.card_tournament_settings for select to anon, authenticated
using (
  exists (
    select 1 from public.tournaments t
    where t.id = card_tournament_settings.tournament_id
      and (
        t.owner_id = (select auth.uid())
        or (t.status <> 'draft' and t.visibility in ('public','unlisted'))
      )
  )
);

drop policy if exists card_rounds_read on public.card_rounds;
create policy card_rounds_read
on public.card_rounds for select to anon, authenticated
using (
  exists (
    select 1 from public.tournaments t
    where t.id = card_rounds.tournament_id
      and (
        t.owner_id = (select auth.uid())
        or (t.status <> 'draft' and t.visibility in ('public','unlisted'))
      )
  )
);

drop policy if exists card_tables_read on public.card_tables;
create policy card_tables_read
on public.card_tables for select to anon, authenticated
using (
  exists (
    select 1
    from public.card_rounds r
    join public.tournaments t on t.id = r.tournament_id
    where r.id = card_tables.round_id
      and (
        t.owner_id = (select auth.uid())
        or (t.status <> 'draft' and t.visibility in ('public','unlisted'))
      )
  )
);

drop policy if exists card_table_players_read on public.card_table_players;
create policy card_table_players_read
on public.card_table_players for select to anon, authenticated
using (
  exists (
    select 1
    from public.card_rounds r
    join public.tournaments t on t.id = r.tournament_id
    where r.id = card_table_players.round_id
      and (
        t.owner_id = (select auth.uid())
        or (t.status <> 'draft' and t.visibility in ('public','unlisted'))
      )
  )
);

revoke all on public.card_tournament_settings, public.card_rounds, public.card_tables, public.card_table_players
  from anon, authenticated;
grant select on public.card_tournament_settings, public.card_rounds, public.card_tables, public.card_table_players
  to anon, authenticated;
grant all on public.card_tournament_settings, public.card_rounds, public.card_tables, public.card_table_players
  to service_role;

create or replace function public.get_card_tournament_state(p_tournament_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_tournament public.tournaments%rowtype;
  v_settings public.card_tournament_settings%rowtype;
  v_series_id uuid;
  v_series_title text;
  v_result jsonb;
begin
  select * into v_tournament
  from public.tournaments
  where id = p_tournament_id;

  if v_tournament.id is null then raise exception 'CARD_TOURNAMENT_NOT_FOUND'; end if;
  if (select auth.uid()) is null then raise exception 'AUTHENTICATION_REQUIRED'; end if;
  if v_tournament.owner_id <> (select auth.uid())
     and not coalesce(public.is_admin((select auth.uid())), false) then
    raise exception 'CARD_TOURNAMENT_ACCESS_DENIED';
  end if;
  if v_tournament.format <> 'karty' and lower(btrim(v_tournament.sport)) not in ('karty','cards','card') then
    raise exception 'NOT_A_CARD_TOURNAMENT';
  end if;

  select s.* into v_settings
  from public.card_tournament_settings s
  where s.tournament_id = p_tournament_id;

  select es.id, es.title into v_series_id, v_series_title
  from public.events e
  join public.event_series es on es.id = e.series_id
  where e.id = v_tournament.source_event_id;

  select jsonb_build_object(
    'kind','cards',
    'tournament',jsonb_build_object(
      'id',v_tournament.id,'name',v_tournament.name,'sport',v_tournament.sport,
      'discipline',v_tournament.discipline,'format',v_tournament.format,
      'status',v_tournament.status,'date',v_tournament.date,'venue',v_tournament.venue,
      'series_id',v_series_id,'series_title',v_series_title
    ),
    'settings',case when v_settings.tournament_id is null then null else jsonb_build_object(
      'players_per_table',v_settings.players_per_table,
      'final_player_count',v_settings.final_player_count,
      'current_round_number',v_settings.current_round_number,
      'status',v_settings.status
    ) end,
    'players',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',tp.id,'name',tp.name,'seed',tp.seed,'user_id',tp.user_id,
        'player_identity_id',tp.player_identity_id
      ) order by tp.seed nulls last,tp.created_at)
      from public.tournament_players tp
      where tp.tournament_id = p_tournament_id
    ),'[]'::jsonb),
    'rounds',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',r.id,'number',r.round_number,'type',r.round_type,'status',r.status,
        'created_at',r.created_at,'completed_at',r.completed_at,
        'tables',coalesce((
          select jsonb_agg(jsonb_build_object(
            'id',ct.id,'number',ct.table_number,'name',ct.label,'status',ct.status,
            'players',coalesce((
              select jsonb_agg(jsonb_build_object(
                'id',tp.id,'name',tp.name,'seat',ctp.seat_number,
                'outcome',ctp.outcome,'final_position',ctp.final_position
              ) order by ctp.seat_number)
              from public.card_table_players ctp
              join public.tournament_players tp on tp.id = ctp.tournament_player_id
              where ctp.table_id = ct.id
            ),'[]'::jsonb)
          ) order by ct.table_number)
          from public.card_tables ct where ct.round_id = r.id
        ),'[]'::jsonb)
      ) order by r.round_number)
      from public.card_rounds r where r.tournament_id = p_tournament_id
    ),'[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.get_card_tournament_state(uuid) from public;
grant execute on function public.get_card_tournament_state(uuid) to authenticated, service_role;

create or replace function public.start_card_tournament(
  p_tournament_id uuid,
  p_players_per_table integer default 4,
  p_table_count integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tournament public.tournaments%rowtype;
  v_player_count integer;
  v_final_count integer := 4;
  v_table_count integer;
  v_round_id uuid;
begin
  select * into v_tournament
  from public.tournaments
  where id = p_tournament_id
    and (owner_id = (select auth.uid()) or public.is_admin((select auth.uid())))
  for update;

  if v_tournament.id is null then raise exception 'CARD_TOURNAMENT_NOT_FOUND_OR_FORBIDDEN'; end if;
  if v_tournament.format <> 'karty' then raise exception 'NOT_A_CARD_TOURNAMENT'; end if;
  if v_tournament.status in ('completed','archived') then raise exception 'CARD_TOURNAMENT_ALREADY_COMPLETED'; end if;
  if p_players_per_table < 2 or p_players_per_table > 8 then raise exception 'PLAYERS_PER_TABLE_MUST_BE_2_TO_8'; end if;
  if exists(select 1 from public.card_rounds where tournament_id = p_tournament_id) then
    raise exception 'CARD_TOURNAMENT_ALREADY_STARTED';
  end if;

  select count(*)::integer into v_player_count
  from public.tournament_players where tournament_id = p_tournament_id;
  if v_player_count < v_final_count then raise exception 'CARD_TOURNAMENT_REQUIRES_AT_LEAST_FOUR_PLAYERS'; end if;
  if exists(
    select 1 from public.tournament_players
    where tournament_id = p_tournament_id and player_identity_id is null
  ) then raise exception 'CARD_TOURNAMENT_REQUIRES_PLAYER_IDENTITIES'; end if;

  v_table_count := case
    when v_player_count = v_final_count then 1
    else greatest(1,least(
      floor(v_player_count::numeric / 2)::integer,
      coalesce(p_table_count,ceil(v_player_count::numeric / p_players_per_table)::integer)
    ))
  end;

  insert into public.card_tournament_settings(
    tournament_id,players_per_table,final_player_count,current_round_number,status
  ) values (p_tournament_id,p_players_per_table,v_final_count,1,'in_progress')
  on conflict (tournament_id) do update set
    players_per_table=excluded.players_per_table,
    final_player_count=excluded.final_player_count,
    current_round_number=1,
    status='in_progress';

  insert into public.card_rounds(tournament_id,round_number,round_type,status)
  values(p_tournament_id,1,case when v_player_count=v_final_count then 'final' else 'qualification' end,'open')
  returning id into v_round_id;

  insert into public.card_tables(round_id,table_number,label,status)
  select v_round_id,n,'Stôl '||n,'open'
  from generate_series(1,v_table_count) n;

  with ordered as (
    select tp.id,
      row_number() over(order by md5(tp.id::text||':1:'||p_tournament_id::text)) as rn
    from public.tournament_players tp
    where tp.tournament_id = p_tournament_id
  )
  insert into public.card_table_players(table_id,round_id,tournament_player_id,seat_number)
  select ct.id,v_round_id,o.id,(((o.rn-1)/v_table_count)+1)::smallint
  from ordered o
  join public.card_tables ct
    on ct.round_id=v_round_id
   and ct.table_number=((o.rn-1)%v_table_count)+1;

  update public.tournaments
  set status='active',started_at=coalesce(started_at,now()),
      config=coalesce(config,'{}'::jsonb)||jsonb_build_object(
        'card_players_per_table',p_players_per_table,
        'card_final_player_count',v_final_count
      )
  where id=p_tournament_id;

  return public.get_card_tournament_state(p_tournament_id);
end;
$$;

revoke all on function public.start_card_tournament(uuid,integer,integer) from public;
grant execute on function public.start_card_tournament(uuid,integer,integer) to authenticated, service_role;

create or replace function public.set_card_player_eliminated(
  p_table_id uuid,
  p_tournament_player_id uuid,
  p_eliminated boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tournament_id uuid;
  v_round_id uuid;
  v_round_type text;
  v_table_status text;
  v_other_active integer;
begin
  select r.tournament_id,r.id,r.round_type,ct.status
  into v_tournament_id,v_round_id,v_round_type,v_table_status
  from public.card_tables ct
  join public.card_rounds r on r.id=ct.round_id
  join public.tournaments t on t.id=r.tournament_id
  where ct.id=p_table_id
    and (t.owner_id=(select auth.uid()) or public.is_admin((select auth.uid())))
  for update of ct;

  if v_tournament_id is null then raise exception 'CARD_TABLE_NOT_FOUND_OR_FORBIDDEN'; end if;
  if v_round_type='final' then raise exception 'FINAL_TABLE_USES_PLACEMENTS'; end if;
  if v_table_status<>'open' then raise exception 'CARD_TABLE_IS_CLOSED'; end if;
  if not exists(
    select 1 from public.card_table_players
    where table_id=p_table_id and tournament_player_id=p_tournament_player_id
  ) then raise exception 'PLAYER_IS_NOT_AT_THIS_TABLE'; end if;

  if p_eliminated then
    select count(*)::integer into v_other_active
    from public.card_table_players
    where table_id=p_table_id
      and tournament_player_id<>p_tournament_player_id
      and outcome='active';
    if v_other_active<1 then raise exception 'AT_LEAST_ONE_PLAYER_MUST_ADVANCE_FROM_TABLE'; end if;
  end if;

  update public.card_table_players
  set outcome=case when p_eliminated then 'eliminated' else 'active' end,
      final_position=null,updated_at=now()
  where table_id=p_table_id and tournament_player_id=p_tournament_player_id;

  return public.get_card_tournament_state(v_tournament_id);
end;
$$;

revoke all on function public.set_card_player_eliminated(uuid,uuid,boolean) from public;
grant execute on function public.set_card_player_eliminated(uuid,uuid,boolean) to authenticated, service_role;

create or replace function public.set_card_table_status(p_table_id uuid,p_status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tournament_id uuid;
  v_round_id uuid;
  v_round_number integer;
  v_round_type text;
  v_active integer;
  v_eliminated integer;
begin
  if p_status not in ('open','completed') then raise exception 'INVALID_CARD_TABLE_STATUS'; end if;

  select r.tournament_id,r.id,r.round_number,r.round_type
  into v_tournament_id,v_round_id,v_round_number,v_round_type
  from public.card_tables ct
  join public.card_rounds r on r.id=ct.round_id
  join public.tournaments t on t.id=r.tournament_id
  where ct.id=p_table_id
    and (t.owner_id=(select auth.uid()) or public.is_admin((select auth.uid())))
  for update of ct;

  if v_tournament_id is null then raise exception 'CARD_TABLE_NOT_FOUND_OR_FORBIDDEN'; end if;
  if v_round_type='final' then raise exception 'FINAL_TABLE_IS_COMPLETED_WITH_TOURNAMENT'; end if;
  if exists(select 1 from public.card_rounds where tournament_id=v_tournament_id and round_number>v_round_number) then
    raise exception 'PAST_CARD_ROUND_IS_LOCKED';
  end if;

  if p_status='completed' then
    select
      count(*) filter(where outcome='active')::integer,
      count(*) filter(where outcome='eliminated')::integer
    into v_active,v_eliminated
    from public.card_table_players where table_id=p_table_id;
    if v_active<1 then raise exception 'AT_LEAST_ONE_PLAYER_MUST_ADVANCE_FROM_TABLE'; end if;
    if v_eliminated<1 then raise exception 'MARK_AT_LEAST_ONE_ELIMINATED_PLAYER'; end if;
  end if;

  update public.card_tables set status=p_status where id=p_table_id;
  return public.get_card_tournament_state(v_tournament_id);
end;
$$;

revoke all on function public.set_card_table_status(uuid,text) from public;
grant execute on function public.set_card_table_status(uuid,text) to authenticated, service_role;

create or replace function public.advance_card_round(p_tournament_id uuid)
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
  v_table_count integer;
  v_next_number integer;
begin
  select s.* into v_settings
  from public.card_tournament_settings s
  join public.tournaments t on t.id=s.tournament_id
  where s.tournament_id=p_tournament_id
    and (t.owner_id=(select auth.uid()) or public.is_admin((select auth.uid())))
  for update of s;

  if v_settings.tournament_id is null then raise exception 'CARD_TOURNAMENT_NOT_FOUND_OR_FORBIDDEN'; end if;
  if v_settings.status<>'in_progress' then raise exception 'CARD_TOURNAMENT_IS_NOT_RUNNING'; end if;

  select * into v_current_round
  from public.card_rounds
  where tournament_id=p_tournament_id and round_number=v_settings.current_round_number
  for update;

  if v_current_round.id is null or v_current_round.round_type='final' then
    raise exception 'CARD_FINAL_ROUND_CANNOT_ADVANCE';
  end if;
  if exists(select 1 from public.card_tables where round_id=v_current_round.id and status<>'completed') then
    raise exception 'ALL_CARD_TABLES_MUST_BE_COMPLETED';
  end if;

  select count(*)::integer into v_survivor_count
  from public.card_table_players
  where round_id=v_current_round.id and outcome='active';

  if v_survivor_count<v_settings.final_player_count then raise exception 'TOO_FEW_PLAYERS_FOR_FINAL'; end if;
  if v_survivor_count=(select count(*) from public.card_table_players where round_id=v_current_round.id) then
    raise exception 'AT_LEAST_ONE_PLAYER_MUST_BE_ELIMINATED';
  end if;

  v_next_number:=v_current_round.round_number+1;
  v_table_count:=case when v_survivor_count=v_settings.final_player_count then 1 else
    greatest(1,least(
      floor(v_survivor_count::numeric/2)::integer,
      ceil(v_survivor_count::numeric/v_settings.players_per_table)::integer
    )) end;

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
  from generate_series(1,v_table_count) n;

  with survivors as (
    select ctp.tournament_player_id as id,
      row_number() over(order by md5(ctp.tournament_player_id::text||':'||v_next_number::text||':'||p_tournament_id::text)) as rn
    from public.card_table_players ctp
    where ctp.round_id=v_current_round.id and ctp.outcome='active'
  )
  insert into public.card_table_players(table_id,round_id,tournament_player_id,seat_number)
  select ct.id,v_next_round_id,s.id,(((s.rn-1)/v_table_count)+1)::smallint
  from survivors s
  join public.card_tables ct
    on ct.round_id=v_next_round_id
   and ct.table_number=((s.rn-1)%v_table_count)+1;

  update public.card_tournament_settings
  set current_round_number=v_next_number
  where tournament_id=p_tournament_id;

  return public.get_card_tournament_state(p_tournament_id);
end;
$$;

revoke all on function public.advance_card_round(uuid) from public;
grant execute on function public.advance_card_round(uuid) to authenticated, service_role;

create or replace function public.complete_card_tournament(p_tournament_id uuid,p_placements jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_settings public.card_tournament_settings%rowtype;
  v_final_round public.card_rounds%rowtype;
  v_final_count integer;
  v_total_players integer;
begin
  select s.* into v_settings
  from public.card_tournament_settings s
  join public.tournaments t on t.id=s.tournament_id
  where s.tournament_id=p_tournament_id
    and (t.owner_id=(select auth.uid()) or public.is_admin((select auth.uid())))
  for update of s;

  if v_settings.tournament_id is null then raise exception 'CARD_TOURNAMENT_NOT_FOUND_OR_FORBIDDEN'; end if;
  if v_settings.status<>'in_progress' then raise exception 'CARD_TOURNAMENT_IS_NOT_RUNNING'; end if;
  if jsonb_typeof(p_placements)<>'array' then raise exception 'CARD_PLACEMENTS_MUST_BE_ARRAY'; end if;

  select * into v_final_round
  from public.card_rounds
  where tournament_id=p_tournament_id and round_number=v_settings.current_round_number
  for update;

  if v_final_round.id is null or v_final_round.round_type<>'final' then
    raise exception 'CARD_FINAL_ROUND_REQUIRED';
  end if;

  select count(*)::integer into v_final_count
  from public.card_table_players where round_id=v_final_round.id;
  if jsonb_array_length(p_placements)<>v_final_count then raise exception 'ALL_FINALISTS_REQUIRE_PLACEMENT'; end if;
  if exists(
    select 1
    from jsonb_to_recordset(p_placements) x(tournament_player_id uuid,final_position integer)
    where x.final_position<1 or x.final_position>v_final_count
  ) then raise exception 'INVALID_FINAL_POSITION'; end if;
  if (select count(distinct x.final_position) from jsonb_to_recordset(p_placements) x(tournament_player_id uuid,final_position integer))<>v_final_count then
    raise exception 'FINAL_POSITIONS_MUST_BE_UNIQUE';
  end if;
  if exists(
    select 1
    from jsonb_to_recordset(p_placements) x(tournament_player_id uuid,final_position integer)
    where not exists(
      select 1 from public.card_table_players ctp
      where ctp.round_id=v_final_round.id and ctp.tournament_player_id=x.tournament_player_id
    )
  ) then raise exception 'INVALID_CARD_FINALIST'; end if;

  update public.card_table_players ctp
  set outcome='placed',final_position=x.final_position,updated_at=now()
  from jsonb_to_recordset(p_placements) x(tournament_player_id uuid,final_position integer)
  where ctp.round_id=v_final_round.id and ctp.tournament_player_id=x.tournament_player_id;

  update public.card_tables set status='completed' where round_id=v_final_round.id;
  update public.card_rounds set status='completed',completed_at=coalesce(completed_at,now()) where id=v_final_round.id;
  update public.card_tournament_settings set status='completed' where tournament_id=p_tournament_id;

  select count(*)::integer into v_total_players
  from public.tournament_players where tournament_id=p_tournament_id;

  if (
    select count(distinct tournament_player_id)
    from public.card_table_players
    where tournament_player_id in (
      select id from public.tournament_players where tournament_id=p_tournament_id
    ) and (outcome='eliminated' or (round_id=v_final_round.id and outcome='placed'))
  )<>v_total_players then raise exception 'EVERY_CARD_PLAYER_REQUIRES_FINAL_RESULT'; end if;

  with eliminated as (
    select ctp.tournament_player_id,max(r.round_number)::integer as elimination_round
    from public.card_table_players ctp
    join public.card_rounds r on r.id=ctp.round_id
    where r.tournament_id=p_tournament_id and ctp.outcome='eliminated'
    group by ctp.tournament_player_id
  ), finalists as (
    select ctp.tournament_player_id,ctp.final_position
    from public.card_table_players ctp
    where ctp.round_id=v_final_round.id and ctp.outcome='placed'
  ), positions as (
    select tp.id as tournament_player_id,
      coalesce(
        f.final_position,
        v_final_count+1+(
          select count(*)::integer from eliminated later
          where later.elimination_round>e.elimination_round
        )
      )::integer as final_position,
      e.elimination_round
    from public.tournament_players tp
    left join finalists f on f.tournament_player_id=tp.id
    left join eliminated e on e.tournament_player_id=tp.id
    where tp.tournament_id=p_tournament_id
  ), played as (
    select ctp.tournament_player_id,count(distinct ctp.round_id)::integer as rounds_played
    from public.card_table_players ctp
    join public.card_rounds r on r.id=ctp.round_id
    where r.tournament_id=p_tournament_id
    group by ctp.tournament_player_id
  )
  insert into public.tournament_results(
    tournament_id,tournament_player_id,user_id,final_position,
    matches_played,wins,losses,score_for,score_against,metadata
  )
  select p_tournament_id,tp.id,tp.user_id,p.final_position,
    coalesce(pl.rounds_played,0),0,case when p.final_position>v_final_count then 1 else 0 end,0,0,
    jsonb_build_object(
      'format','cards','rounds_played',coalesce(pl.rounds_played,0),
      'elimination_round',p.elimination_round
    )
  from public.tournament_players tp
  join positions p on p.tournament_player_id=tp.id
  left join played pl on pl.tournament_player_id=tp.id
  where tp.tournament_id=p_tournament_id
  on conflict(tournament_id,tournament_player_id) do update set
    user_id=excluded.user_id,final_position=excluded.final_position,
    matches_played=excluded.matches_played,wins=excluded.wins,losses=excluded.losses,
    score_for=0,score_against=0,metadata=excluded.metadata,updated_at=now();

  update public.tournament_phases
  set status='completed',completed_at=coalesce(completed_at,now())
  where tournament_id=p_tournament_id and status<>'completed';

  update public.tournaments
  set status='completed',completed_at=coalesce(completed_at,now())
  where id=p_tournament_id;

  return public.get_card_tournament_state(p_tournament_id);
end;
$$;

revoke all on function public.complete_card_tournament(uuid,jsonb) from public;
grant execute on function public.complete_card_tournament(uuid,jsonb) to authenticated, service_role;

create or replace function public.reset_card_tournament(p_tournament_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tournament public.tournaments%rowtype;
begin
  select * into v_tournament
  from public.tournaments
  where id=p_tournament_id
    and (owner_id=(select auth.uid()) or public.is_admin((select auth.uid())))
  for update;
  if v_tournament.id is null then raise exception 'CARD_TOURNAMENT_NOT_FOUND_OR_FORBIDDEN'; end if;
  if v_tournament.status in ('completed','archived') then raise exception 'COMPLETED_CARD_TOURNAMENT_IS_LOCKED'; end if;

  delete from public.card_rounds where tournament_id=p_tournament_id;
  delete from public.card_tournament_settings where tournament_id=p_tournament_id;
  delete from public.tournament_results where tournament_id=p_tournament_id;
  update public.tournaments
  set status='draft',started_at=null,completed_at=null,
      config=coalesce(config,'{}'::jsonb)-'card_players_per_table'-'card_final_player_count'
  where id=p_tournament_id;
  return public.get_card_tournament_state(p_tournament_id);
end;
$$;

revoke all on function public.reset_card_tournament(uuid) from public;
grant execute on function public.reset_card_tournament(uuid) to authenticated, service_role;

create or replace function public.get_card_display_payload(p_tournament_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_tournament public.tournaments%rowtype;
  v_settings public.card_tournament_settings%rowtype;
  v_round public.card_rounds%rowtype;
begin
  select * into v_tournament from public.tournaments where id=p_tournament_id;
  if v_tournament.id is null or v_tournament.format<>'karty' then return null; end if;
  if not (
    v_tournament.owner_id=(select auth.uid())
    or public.is_admin((select auth.uid()))
    or (v_tournament.status<>'draft' and v_tournament.visibility in ('public','unlisted'))
  ) then return null; end if;

  select * into v_settings from public.card_tournament_settings where tournament_id=p_tournament_id;
  if v_settings.tournament_id is null then
    return jsonb_build_object('kind','cards','tournament',jsonb_build_object(
      'id',v_tournament.id,'name',v_tournament.name,'sport',v_tournament.sport,
      'discipline',v_tournament.discipline,'status',v_tournament.status
    ),'round',null,'items','[]'::jsonb);
  end if;

  select * into v_round from public.card_rounds
  where tournament_id=p_tournament_id and round_number=v_settings.current_round_number;

  return jsonb_build_object(
    'kind','cards',
    'tournament',jsonb_build_object(
      'id',v_tournament.id,'name',v_tournament.name,'sport',v_tournament.sport,
      'discipline',v_tournament.discipline,'status',v_tournament.status,
      'date',v_tournament.date,'venue',v_tournament.venue
    ),
    'round',case when v_round.id is null then null else jsonb_build_object(
      'id',v_round.id,'number',v_round.round_number,'type',v_round.round_type,'status',v_round.status
    ) end,
    'items',coalesce((
      select jsonb_agg(jsonb_build_object(
        'table_id',ct.id,'table_number',ct.table_number,'table_label',ct.label,
        'status',ct.status,'players',coalesce((
          select jsonb_agg(jsonb_build_object(
            'id',tp.id,'name',tp.name,'seat',ctp.seat_number,
            'outcome',ctp.outcome,'final_position',ctp.final_position
          ) order by ctp.seat_number)
          from public.card_table_players ctp
          join public.tournament_players tp on tp.id=ctp.tournament_player_id
          where ctp.table_id=ct.id
        ),'[]'::jsonb)
      ) order by ct.table_number)
      from public.card_tables ct where ct.round_id=v_round.id
    ),'[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_card_display_payload(uuid) from public;
grant execute on function public.get_card_display_payload(uuid) to anon, authenticated, service_role;

-- Supabase may have explicit default EXECUTE grants for `anon`. Keep only the
-- public projector payload anonymous; every state-changing card RPC is owner-only.
revoke execute on function public.get_card_tournament_state(uuid) from anon;
revoke execute on function public.start_card_tournament(uuid,integer,integer) from anon;
revoke execute on function public.set_card_player_eliminated(uuid,uuid,boolean) from anon;
revoke execute on function public.set_card_table_status(uuid,text) from anon;
revoke execute on function public.advance_card_round(uuid) from anon;
revoke execute on function public.complete_card_tournament(uuid,jsonb) from anon;
revoke execute on function public.reset_card_tournament(uuid) from anon;

create or replace function private.apply_event_series_scoring_preset()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_is_cards boolean := lower(btrim(coalesce(new.sport,''))) in ('karty','cards','card');
  v_new_preset text := coalesce(new.ranking_config->>'preset','');
  v_best jsonb := coalesce(new.ranking_config->'best_results_count','null'::jsonb);
  v_cards jsonb := '{"version":1,"preset":"cards_80","method":"placement_points","best_results_count":null,"attendance_bonus":0,"points":[{"min_position":1,"max_position":1,"points":80},{"min_position":2,"max_position":2,"points":60},{"min_position":3,"max_position":3,"points":48},{"min_position":4,"max_position":4,"points":40},{"min_position":5,"max_position":6,"points":28},{"min_position":7,"max_position":8,"points":20},{"min_position":9,"max_position":null,"points":12}],"tie_breakers":["victories","runner_up_finishes","third_places","best_position"]}'::jsonb;
  v_sports jsonb := '{"version":2,"preset":"kanianka_200","method":"placement_points","best_results_count":null,"attendance_bonus":0,"points":[{"min_position":1,"max_position":1,"points":200},{"min_position":2,"max_position":2,"points":150},{"min_position":3,"max_position":3,"points":120},{"min_position":4,"max_position":4,"points":100},{"min_position":5,"max_position":6,"points":70},{"min_position":7,"max_position":8,"points":50},{"min_position":9,"max_position":null,"points":30}],"tie_breakers":[]}'::jsonb;
begin
  if tg_op='INSERT' then
    if v_is_cards then new.ranking_config:=jsonb_set(v_cards,'{best_results_count}',v_best,true); end if;
  elsif new.sport is distinct from old.sport then
    if v_is_cards and v_new_preset in ('','kanianka_200') then
      new.ranking_config:=jsonb_set(v_cards,'{best_results_count}',v_best,true);
    elsif not v_is_cards and coalesce(old.ranking_config->>'preset','')='cards_80' then
      new.ranking_config:=jsonb_set(v_sports,'{best_results_count}',v_best,true);
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.apply_event_series_scoring_preset() from public,anon,authenticated;

drop trigger if exists event_series_apply_scoring_preset on public.event_series;
create trigger event_series_apply_scoring_preset
before insert or update of sport on public.event_series
for each row execute function private.apply_event_series_scoring_preset();

update public.event_series s
set ranking_config='{"version":1,"preset":"cards_80","method":"placement_points","best_results_count":null,"attendance_bonus":0,"points":[{"min_position":1,"max_position":1,"points":80},{"min_position":2,"max_position":2,"points":60},{"min_position":3,"max_position":3,"points":48},{"min_position":4,"max_position":4,"points":40},{"min_position":5,"max_position":6,"points":28},{"min_position":7,"max_position":8,"points":20},{"min_position":9,"max_position":null,"points":12}],"tie_breakers":["victories","runner_up_finishes","third_places","best_position"]}'::jsonb
where lower(btrim(coalesce(s.sport,''))) in ('karty','cards','card')
  and coalesce(s.ranking_config->>'preset','') in ('','kanianka_200')
  and not exists(
    select 1 from public.events e
    join public.tournaments t on t.source_event_id=e.id
    where e.series_id=s.id and t.status in ('completed','archived')
  );

commit;
