alter table public.matches
  add column if not exists match_clock_elapsed_seconds integer not null default 0,
  add column if not exists match_clock_started_at timestamptz,
  add column if not exists match_clock_paused_at timestamptz,
  add column if not exists match_clock_stopped_at timestamptz;

alter table public.matches drop constraint if exists matches_match_clock_nonnegative;
alter table public.matches add constraint matches_match_clock_nonnegative
  check (match_clock_elapsed_seconds >= 0);

create index if not exists matches_station_live_idx
  on public.matches(station_id,status,updated_at desc)
  where station_id is not null;

create or replace function public.assign_match_to_station(p_match_id uuid, p_station_id uuid)
returns public.matches
language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.matches;
begin
  select m.* into v
  from public.matches m
  join public.tournaments t on t.id=m.tournament_id
  join public.stations s on s.id=p_station_id
  join public.clubs c on c.id=s.club_id
  where m.id=p_match_id
    and (t.owner_id=auth.uid() or c.owner_id=auth.uid() or public.is_admin(auth.uid()))
  for update of m;
  if v.id is null then raise exception 'Match or station not found, or access denied'; end if;

  if exists(select 1 from public.matches x where x.station_id=p_station_id and x.id<>p_match_id and x.status in ('ready','called','player_arriving','live','in_progress')) then
    raise exception 'Station already has an active match';
  end if;

  update public.matches
  set station_id=p_station_id,
      status=case when status='pending' then 'ready' else status end
  where id=p_match_id
  returning * into v;

  insert into public.audit_logs(user_id,entity_type,entity_id,action,metadata)
  values(auth.uid(),'match',p_match_id,'station_assigned',jsonb_build_object('station_id',p_station_id));
  return v;
end $$;

create or replace function public.unassign_match_station(p_match_id uuid)
returns public.matches
language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.matches;
begin
  update public.matches m
  set station_id=null
  from public.tournaments t
  where m.id=p_match_id and t.id=m.tournament_id
    and (t.owner_id=auth.uid() or public.is_admin(auth.uid()))
  returning m.* into v;
  if v.id is null then raise exception 'Match not found or access denied'; end if;
  return v;
end $$;

create or replace function public.start_match_clock(p_match_id uuid)
returns public.matches
language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.matches;
begin
  select m.* into v from public.matches m join public.tournaments t on t.id=m.tournament_id
  where m.id=p_match_id and (t.owner_id=auth.uid() or public.is_admin(auth.uid())) for update of m;
  if v.id is null then raise exception 'Match not found or access denied'; end if;
  if v.match_clock_started_at is null then
    update public.matches set
      match_clock_started_at=now(), match_clock_paused_at=null, match_clock_stopped_at=null,
      started_at=coalesce(started_at,now()), status='in_progress'
    where id=p_match_id returning * into v;
  end if;
  return v;
end $$;

create or replace function public.pause_match_clock(p_match_id uuid)
returns public.matches
language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.matches; add_seconds integer;
begin
  select m.* into v from public.matches m join public.tournaments t on t.id=m.tournament_id
  where m.id=p_match_id and (t.owner_id=auth.uid() or public.is_admin(auth.uid())) for update of m;
  if v.id is null then raise exception 'Match not found or access denied'; end if;
  if v.match_clock_started_at is not null then
    add_seconds:=greatest(extract(epoch from(now()-v.match_clock_started_at))::integer,0);
    update public.matches set
      match_clock_elapsed_seconds=match_clock_elapsed_seconds+add_seconds,
      match_clock_started_at=null, match_clock_paused_at=now(), status='live'
    where id=p_match_id returning * into v;
  end if;
  return v;
end $$;

create or replace function public.stop_match_clock(p_match_id uuid)
returns public.matches
language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.matches; add_seconds integer;
begin
  select m.* into v from public.matches m join public.tournaments t on t.id=m.tournament_id
  where m.id=p_match_id and (t.owner_id=auth.uid() or public.is_admin(auth.uid())) for update of m;
  if v.id is null then raise exception 'Match not found or access denied'; end if;
  add_seconds:=case when v.match_clock_started_at is not null then greatest(extract(epoch from(now()-v.match_clock_started_at))::integer,0) else 0 end;
  update public.matches set
    match_clock_elapsed_seconds=match_clock_elapsed_seconds+add_seconds,
    match_clock_started_at=null, match_clock_paused_at=null, match_clock_stopped_at=now(),
    status=case when status='in_progress' then 'live' else status end
  where id=p_match_id returning * into v;
  return v;
end $$;

create or replace function public.get_station_live_match(p_token text)
returns table(
  station_id uuid, station_name text, station_sport text, lock_mode boolean,
  match_id uuid, tournament_id uuid, tournament_name text, discipline text,
  player1_id uuid, player1_name text, player2_id uuid, player2_name text,
  score1 integer, score2 integer, match_status text,
  elapsed_seconds integer, clock_running boolean, clock_started_at timestamptz
)
language sql stable security definer set search_path=public,pg_temp as $$
  select s.id,s.name,s.sport,s.lock_mode,
         m.id,m.tournament_id,t.name,t.discipline,
         m.player1_id,p1.name,m.player2_id,p2.name,
         m.score1,m.score2,m.status,
         (m.match_clock_elapsed_seconds + case when m.match_clock_started_at is not null then greatest(extract(epoch from(now()-m.match_clock_started_at))::integer,0) else 0 end)::integer,
         (m.match_clock_started_at is not null),m.match_clock_started_at
  from public.stations s
  left join lateral (
    select x.* from public.matches x
    where x.station_id=s.id and x.status in ('ready','called','player_arriving','live','in_progress')
    order by case when x.status='in_progress' then 0 when x.status='live' then 1 else 2 end, x.updated_at desc
    limit 1
  ) m on true
  left join public.tournaments t on t.id=m.tournament_id
  left join public.tournament_players p1 on p1.id=m.player1_id
  left join public.tournament_players p2 on p2.id=m.player2_id
  where s.token=p_token;
$$;

create or replace function public.station_update_match_score(p_token text,p_score1 integer,p_score2 integer)
returns public.matches
language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.matches; sid uuid;
begin
  select id into sid from public.stations where token=p_token;
  if sid is null then raise exception 'Invalid station token'; end if;
  if p_score1<0 or p_score2<0 then raise exception 'Score must be nonnegative'; end if;
  update public.matches set score1=p_score1,score2=p_score2
  where id=(select id from public.matches where station_id=sid and status in ('ready','called','player_arriving','live','in_progress') order by updated_at desc limit 1)
  returning * into v;
  if v.id is null then raise exception 'No active match assigned to station'; end if;
  return v;
end $$;

create or replace function public.station_start_match_clock(p_token text)
returns public.matches language plpgsql security definer set search_path=public,pg_temp as $$
declare mid uuid; v public.matches;
begin
  select m.id into mid from public.matches m join public.stations s on s.id=m.station_id
  where s.token=p_token and m.status in ('ready','called','player_arriving','live','in_progress')
  order by m.updated_at desc limit 1;
  if mid is null then raise exception 'No active match assigned to station'; end if;
  update public.matches set match_clock_started_at=coalesce(match_clock_started_at,now()),match_clock_paused_at=null,match_clock_stopped_at=null,started_at=coalesce(started_at,now()),status='in_progress' where id=mid returning * into v;
  return v;
end $$;

create or replace function public.station_pause_match_clock(p_token text)
returns public.matches language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.matches; mid uuid; add_seconds integer;
begin
  select m.* into v from public.matches m join public.stations s on s.id=m.station_id
  where s.token=p_token and m.status in ('ready','called','player_arriving','live','in_progress')
  order by m.updated_at desc limit 1 for update of m;
  if v.id is null then raise exception 'No active match assigned to station'; end if;
  add_seconds:=case when v.match_clock_started_at is not null then greatest(extract(epoch from(now()-v.match_clock_started_at))::integer,0) else 0 end;
  update public.matches set match_clock_elapsed_seconds=match_clock_elapsed_seconds+add_seconds,match_clock_started_at=null,match_clock_paused_at=now(),status='live' where id=v.id returning * into v;
  return v;
end $$;

revoke execute on function public.assign_match_to_station(uuid,uuid),public.unassign_match_station(uuid),public.start_match_clock(uuid),public.pause_match_clock(uuid),public.stop_match_clock(uuid) from public,anon;
grant execute on function public.assign_match_to_station(uuid,uuid),public.unassign_match_station(uuid),public.start_match_clock(uuid),public.pause_match_clock(uuid),public.stop_match_clock(uuid) to authenticated;

grant execute on function public.get_station_live_match(text),public.station_update_match_score(text,integer,integer),public.station_start_match_clock(text),public.station_pause_match_clock(text) to public,anon,authenticated;

