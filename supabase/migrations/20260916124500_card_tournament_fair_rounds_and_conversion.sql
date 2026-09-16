-- Card tournament improvements: fair per-round table sizing and conversion to league/series.

create or replace function public.card_fair_table_count(
  p_player_count integer,
  p_preferred_players_per_table integer,
  p_final_player_count integer default 4
)
returns integer
language plpgsql
immutable
set search_path = public, pg_temp
as $$
declare
  v_preferred integer;
  v_min_tables integer;
  v_max_tables integer;
  v_candidate integer;
  v_min_size integer;
  v_max_size integer;
  v_imbalance integer;
  v_distance numeric;
  v_best integer := null;
  v_best_imbalance integer := 999;
  v_best_distance numeric := 999;
begin
  if p_player_count is null or p_player_count <= 0 then return 0; end if;
  if p_player_count <= coalesce(p_final_player_count,4) then return 1; end if;

  v_preferred := greatest(2,least(8,coalesce(p_preferred_players_per_table,4)));
  v_min_tables := greatest(1,ceil(p_player_count::numeric / v_preferred)::integer);
  v_max_tables := least(greatest(v_min_tables,floor(p_player_count::numeric / 2)::integer),v_min_tables + 1);

  for v_candidate in v_min_tables..v_max_tables loop
    v_min_size := floor(p_player_count::numeric / v_candidate)::integer;
    v_max_size := ceil(p_player_count::numeric / v_candidate)::integer;

    -- Keep tables close to the selected capacity and avoid one/two-player outliers
    -- when a balanced split one table higher is available.
    if v_min_size < greatest(2,v_preferred - 1) or v_max_size > v_preferred then
      continue;
    end if;

    v_imbalance := v_max_size - v_min_size;
    v_distance := abs((p_player_count::numeric / v_candidate) - v_preferred);

    if v_best is null
       or v_imbalance < v_best_imbalance
       or (v_imbalance = v_best_imbalance and v_distance < v_best_distance) then
      v_best := v_candidate;
      v_best_imbalance := v_imbalance;
      v_best_distance := v_distance;
    end if;
  end loop;

  return coalesce(v_best,v_min_tables);
end;
$$;

revoke all on function public.card_fair_table_count(integer,integer,integer) from public,anon,authenticated;
grant execute on function public.card_fair_table_count(integer,integer,integer) to service_role;

create or replace function public.advance_card_round_configured(
  p_tournament_id uuid,
  p_players_per_table integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_settings public.card_tournament_settings%rowtype;
  v_round_id uuid;
  v_survivor_count integer;
  v_preferred integer;
  v_table_count integer;
  v_effective_capacity integer;
begin
  if auth.uid() is null then raise exception 'AUTHENTICATION_REQUIRED'; end if;

  if not exists(
    select 1 from public.tournaments t
    where t.id=p_tournament_id
      and (t.owner_id=auth.uid() or coalesce(public.is_admin(auth.uid()),false))
  ) then
    raise exception 'CARD_TOURNAMENT_NOT_FOUND_OR_FORBIDDEN';
  end if;

  select * into v_settings
  from public.card_tournament_settings
  where tournament_id=p_tournament_id
  for update;

  if v_settings.tournament_id is null then raise exception 'CARD_TOURNAMENT_NOT_STARTED'; end if;
  if v_settings.status <> 'in_progress' then raise exception 'CARD_TOURNAMENT_NOT_IN_PROGRESS'; end if;

  v_preferred := coalesce(p_players_per_table,v_settings.players_per_table);
  if v_preferred < 2 or v_preferred > 8 then raise exception 'PLAYERS_PER_TABLE_MUST_BE_2_TO_8'; end if;

  select r.id into v_round_id
  from public.card_rounds r
  where r.tournament_id=p_tournament_id
    and r.round_number=v_settings.current_round_number
  for update;

  if v_round_id is null then raise exception 'CURRENT_CARD_ROUND_NOT_FOUND'; end if;

  select count(*)::integer into v_survivor_count
  from public.card_table_players
  where round_id=v_round_id and outcome='active';

  if v_survivor_count < v_settings.final_player_count then
    raise exception 'NOT_ENOUGH_PLAYERS_FOR_NEXT_ROUND';
  end if;

  v_table_count := public.card_fair_table_count(v_survivor_count,v_preferred,v_settings.final_player_count);
  v_effective_capacity := case
    when v_survivor_count <= v_settings.final_player_count then v_settings.final_player_count
    else ceil(v_survivor_count::numeric / greatest(v_table_count,1))::integer
  end;

  update public.card_tournament_settings
  set players_per_table=greatest(2,least(8,v_effective_capacity))
  where tournament_id=p_tournament_id;

  return public.advance_card_round(p_tournament_id);
end;
$$;

revoke all on function public.advance_card_round_configured(uuid,integer) from public,anon;
grant execute on function public.advance_card_round_configured(uuid,integer) to authenticated,service_role;

create or replace function public.create_league_from_tournament(
  p_tournament_id uuid,
  p_name text,
  p_season_name text,
  p_competition_format text default 'round_robin_single',
  p_scheduling_mode text default 'rounds',
  p_visibility text default 'public'
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_t public.tournaments%rowtype;
  v_league_id uuid;
  v_existing uuid;
  v_name text := nullif(btrim(p_name),'');
  v_season text := nullif(btrim(p_season_name),'');
begin
  if v_user is null then raise exception 'AUTHENTICATION_REQUIRED'; end if;

  select * into v_t
  from public.tournaments
  where id=p_tournament_id
    and (owner_id=v_user or coalesce(public.is_admin(v_user),false))
  for update;
  if v_t.id is null then raise exception 'TOURNAMENT_NOT_FOUND_OR_FORBIDDEN'; end if;

  if not coalesce(public.is_admin(v_user),false)
     and not coalesce(public.has_feature_access(v_user,'league_create'::text),false) then
    raise exception 'LEAGUE_FEATURE_NOT_AVAILABLE';
  end if;

  if v_name is null or char_length(v_name)<3 then raise exception 'LEAGUE_NAME_REQUIRED'; end if;
  if v_season is null then raise exception 'LEAGUE_SEASON_REQUIRED'; end if;
  if p_competition_format not in ('round_robin_single','round_robin_double','round_robin_playoff') then raise exception 'INVALID_LEAGUE_FORMAT'; end if;
  if p_scheduling_mode not in ('rounds','open_deadline') then raise exception 'INVALID_LEAGUE_SCHEDULING_MODE'; end if;
  if p_visibility not in ('public','unlisted','private') then raise exception 'INVALID_VISIBILITY'; end if;

  select l.id into v_existing
  from public.leagues l
  where l.owner_id=v_t.owner_id
    and l.config->>'source_tournament_id'=p_tournament_id::text
  order by l.created_at desc limit 1;
  if v_existing is not null then
    return jsonb_build_object('league_id',v_existing,'created',false);
  end if;

  insert into public.leagues(
    owner_id,name,sport,discipline,season_name,competition_format,scheduling_mode,
    status,visibility,starts_on,config
  ) values (
    v_t.owner_id,v_name,v_t.sport,v_t.discipline,v_season,p_competition_format,p_scheduling_mode,
    'draft',p_visibility,v_t.date,
    jsonb_build_object('participant_type','player','source_tournament_id',v_t.id,'source_tournament_name',v_t.name)
  ) returning id into v_league_id;

  insert into public.league_players(league_id,user_id,display_name,seed,status,metadata)
  select v_league_id,tp.user_id,tp.name,tp.seed,'active',
    jsonb_build_object(
      'participant_type','player',
      'source','tournament',
      'source_tournament_id',p_tournament_id,
      'source_tournament_player_id',tp.id,
      'player_identity_id',tp.player_identity_id
    )
  from public.tournament_players tp
  where tp.tournament_id=p_tournament_id
  order by tp.seed nulls last,tp.created_at;

  return jsonb_build_object(
    'league_id',v_league_id,
    'created',true,
    'players_imported',(select count(*) from public.league_players lp where lp.league_id=v_league_id)
  );
end;
$$;

revoke all on function public.create_league_from_tournament(uuid,text,text,text,text,text) from public,anon;
grant execute on function public.create_league_from_tournament(uuid,text,text,text,text,text) to authenticated,service_role;

create or replace function public.create_event_series_from_tournament(
  p_tournament_id uuid,
  p_title text,
  p_starts_at timestamptz[],
  p_visibility text default 'public'
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_t public.tournaments%rowtype;
  v_source public.events%rowtype;
  v_series_id uuid;
  v_event_id uuid;
  v_first_event_id uuid;
  v_event_ids jsonb := '[]'::jsonb;
  v_count integer;
  v_i integer;
  v_title text := nullif(btrim(p_title),'');
begin
  if v_user is null then raise exception 'AUTHENTICATION_REQUIRED'; end if;

  select * into v_t
  from public.tournaments
  where id=p_tournament_id
    and (owner_id=v_user or coalesce(public.is_admin(v_user),false))
  for update;
  if v_t.id is null then raise exception 'TOURNAMENT_NOT_FOUND_OR_FORBIDDEN'; end if;

  v_count:=coalesce(cardinality(p_starts_at),0);
  if v_count<2 or v_count>52 then raise exception 'SERIES_ROUND_COUNT_MUST_BE_2_TO_52'; end if;
  if v_title is null then raise exception 'SERIES_TITLE_REQUIRED'; end if;
  if p_visibility not in ('public','unlisted','private') then raise exception 'INVALID_VISIBILITY'; end if;
  if exists(select 1 from unnest(p_starts_at) d where d is null) then raise exception 'SERIES_DATE_REQUIRED'; end if;
  if (select count(distinct d) from unnest(p_starts_at) d)<>v_count then raise exception 'SERIES_DATES_MUST_BE_UNIQUE'; end if;
  if exists(
    select 1 from generate_subscripts(p_starts_at,1) s(i)
    where s.i>1 and p_starts_at[s.i]<=p_starts_at[s.i-1]
  ) then raise exception 'SERIES_DATES_MUST_BE_ASCENDING'; end if;

  if v_t.source_event_id is not null then
    select * into v_source from public.events where id=v_t.source_event_id for update;
    if v_source.series_id is not null then
      return jsonb_build_object('series_id',v_source.series_id,'first_event_id',v_source.id,'created',false);
    end if;
  end if;

  insert into public.event_series(
    owner_id,title,event_type,sport,discipline,total_rounds,status,visibility
  ) values (
    v_t.owner_id,v_title,'Turnaj',v_t.sport,v_t.discipline,v_count,'published',p_visibility
  ) returning id into v_series_id;

  for v_i in 1..v_count loop
    if v_i=1 and v_source.id is not null then
      update public.events
      set title=v_title,event_type='Turnaj',sport=v_t.sport,discipline=v_t.discipline,
          location_text=coalesce(v_t.venue,location_text),city=coalesce(v_t.city,city),
          starts_at=p_starts_at[v_i],visibility=p_visibility,status='published',
          series_id=v_series_id,series_round_number=v_i
      where id=v_source.id
      returning id into v_event_id;
    else
      insert into public.events(
        owner_id,title,event_type,sport,discipline,location_text,city,starts_at,
        visibility,status,series_id,series_round_number
      ) values (
        v_t.owner_id,v_title,'Turnaj',v_t.sport,v_t.discipline,v_t.venue,v_t.city,p_starts_at[v_i],
        p_visibility,'published',v_series_id,v_i
      ) returning id into v_event_id;
    end if;

    if v_i=1 then v_first_event_id:=v_event_id; end if;
    v_event_ids:=v_event_ids||jsonb_build_array(v_event_id);
  end loop;

  update public.tournaments
  set source_event_id=v_first_event_id,
      config=coalesce(config,'{}'::jsonb)||jsonb_build_object('source_series_id',v_series_id)
  where id=p_tournament_id;

  return jsonb_build_object(
    'series_id',v_series_id,
    'first_event_id',v_first_event_id,
    'round_count',v_count,
    'event_ids',v_event_ids,
    'created',true
  );
end;
$$;

revoke all on function public.create_event_series_from_tournament(uuid,text,timestamptz[],text) from public,anon;
grant execute on function public.create_event_series_from_tournament(uuid,text,timestamptz[],text) to authenticated,service_role;
