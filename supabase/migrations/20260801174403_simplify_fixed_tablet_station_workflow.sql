alter table public.tournament_resources
  add column if not exists tablet_paired_at timestamptz,
  add column if not exists tablet_last_seen_at timestamptz,
  add column if not exists tablet_name text;

create or replace function public.assign_tournament_match(p_resource_id uuid, p_match_id uuid)
returns public.matches
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_resource public.tournament_resources;
  v_match public.matches;
begin
  select r.* into v_resource
  from public.tournament_resources r
  join public.tournaments t on t.id = r.tournament_id
  where r.id = p_resource_id
    and r.is_active = true
    and (t.owner_id = auth.uid() or public.is_admin(auth.uid()))
  for update of r;

  if v_resource.id is null then
    raise exception 'Resource not found or access denied';
  end if;

  if v_resource.status not in ('available','assigned') or v_resource.current_match_id is not null then
    raise exception 'Resource is not available';
  end if;

  select * into v_match
  from public.matches
  where id = p_match_id
    and tournament_id = v_resource.tournament_id
  for update;

  if v_match.id is null then
    raise exception 'Match does not belong to this tournament';
  end if;
  if v_match.player1_id is null or v_match.player2_id is null then
    raise exception 'Match does not have both players';
  end if;
  if v_match.status in ('completed','forfeited') then
    raise exception 'Match is already closed';
  end if;
  if v_match.tournament_resource_id is not null and v_match.tournament_resource_id <> p_resource_id then
    raise exception 'Match is already assigned to another resource';
  end if;

  update public.tournament_resources
  set current_match_id = p_match_id,
      status = 'assigned',
      updated_at = now()
  where id = p_resource_id;

  update public.matches
  set tournament_resource_id = p_resource_id,
      tournament_resource_label = v_resource.label,
      player1_ready_at = null,
      player2_ready_at = null,
      started_at = null,
      completed_at = null,
      match_call_status = 'called',
      called_at = coalesce(called_at, now()),
      status = case when status in ('pending','waiting_for_table','ready') then 'called' else status end,
      updated_at = now()
  where id = p_match_id
  returning * into v_match;

  insert into public.tournament_resource_assignments
    (tournament_id, resource_id, match_id, assigned_by)
  values
    (v_resource.tournament_id, p_resource_id, p_match_id, auth.uid());

  return v_match;
end;
$$;

create or replace function public.get_station_tablet_state(p_device_token uuid)
returns table(
  resource_id uuid,
  tournament_id uuid,
  resource_number integer,
  resource_label text,
  resource_type text,
  resource_status text,
  tablet_name text,
  match_id uuid,
  match_token uuid,
  tournament_name text,
  sport text,
  discipline text,
  round_key text,
  match_number integer,
  player1_id uuid,
  player1_name text,
  player1_present boolean,
  player1_ready_at timestamptz,
  player2_id uuid,
  player2_name text,
  player2_present boolean,
  player2_ready_at timestamptz,
  both_players_present boolean,
  can_start boolean,
  score1 integer,
  score2 integer,
  match_status text,
  started_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.tournament_resources
  set tablet_last_seen_at = now(),
      tablet_paired_at = coalesce(tablet_paired_at, now()),
      updated_at = now()
  where device_token = p_device_token
    and is_active = true;

  return query
  select
    r.id,
    r.tournament_id,
    r.resource_number,
    r.label,
    r.resource_type,
    r.status,
    r.tablet_name,
    m.id,
    m.public_token,
    t.name,
    t.sport,
    t.discipline,
    m.round_key,
    m.match_number,
    m.player1_id,
    p1.name,
    (m.player1_ready_at is not null),
    m.player1_ready_at,
    m.player2_id,
    p2.name,
    (m.player2_ready_at is not null),
    m.player2_ready_at,
    (m.player1_ready_at is not null and m.player2_ready_at is not null),
    (m.id is not null
      and m.player1_ready_at is not null
      and m.player2_ready_at is not null
      and m.started_at is null
      and m.status in ('called','player_arriving','ready')),
    coalesce(m.score1,0),
    coalesce(m.score2,0),
    m.status,
    m.started_at
  from public.tournament_resources r
  join public.tournaments t on t.id = r.tournament_id
  left join public.matches m on m.id = r.current_match_id
  left join public.tournament_players p1 on p1.id = m.player1_id
  left join public.tournament_players p2 on p2.id = m.player2_id
  where r.device_token = p_device_token
    and r.is_active = true;
end;
$$;

create or replace function public.confirm_station_player_presence(
  p_device_token uuid,
  p_player_id uuid
)
returns table(
  match_id uuid,
  player1_present boolean,
  player2_present boolean,
  both_players_present boolean,
  can_start boolean
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_resource public.tournament_resources;
  v_match public.matches;
begin
  select * into v_resource
  from public.tournament_resources
  where device_token = p_device_token
    and is_active = true
  for update;

  if v_resource.id is null then
    raise exception 'Tablet is not paired with an active tournament resource';
  end if;
  if v_resource.current_match_id is null then
    raise exception 'No match is assigned to this resource';
  end if;

  select * into v_match
  from public.matches
  where id = v_resource.current_match_id
    and tournament_id = v_resource.tournament_id
  for update;

  if v_match.id is null then
    raise exception 'Assigned match was not found';
  end if;
  if v_match.started_at is not null or v_match.status in ('live','in_progress','completed','forfeited') then
    raise exception 'Presence can no longer be changed for this match';
  end if;
  if p_player_id = v_match.player1_id then
    update public.matches
    set player1_ready_at = coalesce(player1_ready_at, now()),
        status = 'player_arriving',
        match_call_status = 'arrival_window',
        updated_at = now()
    where id = v_match.id;
  elsif p_player_id = v_match.player2_id then
    update public.matches
    set player2_ready_at = coalesce(player2_ready_at, now()),
        status = 'player_arriving',
        match_call_status = 'arrival_window',
        updated_at = now()
    where id = v_match.id;
  else
    raise exception 'Player does not belong to the assigned match';
  end if;

  update public.matches
  set status = 'ready',
      updated_at = now()
  where id = v_match.id
    and player1_ready_at is not null
    and player2_ready_at is not null;

  update public.tournament_resources
  set tablet_last_seen_at = now(),
      updated_at = now()
  where id = v_resource.id;

  return query
  select m.id,
         m.player1_ready_at is not null,
         m.player2_ready_at is not null,
         m.player1_ready_at is not null and m.player2_ready_at is not null,
         m.player1_ready_at is not null and m.player2_ready_at is not null
           and m.started_at is null and m.status = 'ready'
  from public.matches m
  where m.id = v_match.id;
end;
$$;

create or replace function public.start_station_match(p_device_token uuid)
returns table(
  match_id uuid,
  match_token uuid,
  resource_id uuid,
  resource_label text,
  match_status text,
  started_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_resource public.tournament_resources;
  v_match public.matches;
begin
  select * into v_resource
  from public.tournament_resources
  where device_token = p_device_token
    and is_active = true
  for update;

  if v_resource.id is null then
    raise exception 'Tablet is not paired with an active tournament resource';
  end if;
  if v_resource.current_match_id is null then
    raise exception 'No match is assigned to this resource';
  end if;

  select * into v_match
  from public.matches
  where id = v_resource.current_match_id
    and tournament_id = v_resource.tournament_id
  for update;

  if v_match.id is null then
    raise exception 'Assigned match was not found';
  end if;
  if v_match.player1_ready_at is null or v_match.player2_ready_at is null then
    raise exception 'Both players must confirm their presence';
  end if;
  if v_match.status in ('completed','forfeited') then
    raise exception 'Match is already closed';
  end if;

  update public.matches
  set status = 'in_progress',
      started_at = coalesce(started_at, now()),
      match_clock_started_at = coalesce(match_clock_started_at, now()),
      match_clock_paused_at = null,
      match_clock_stopped_at = null,
      match_call_status = 'closed',
      updated_at = now()
  where id = v_match.id
  returning * into v_match;

  update public.tournament_resources
  set status = 'in_progress',
      tablet_last_seen_at = now(),
      updated_at = now()
  where id = v_resource.id;

  update public.tournament_resource_assignments
  set started_at = coalesce(started_at, now())
  where resource_id = v_resource.id
    and match_id = v_match.id
    and released_at is null;

  return query
  select v_match.id, v_match.public_token, v_resource.id, v_resource.label,
         v_match.status, v_match.started_at;
end;
$$;

create or replace function public.set_tournament_tablet_name(
  p_resource_id uuid,
  p_tablet_name text
)
returns public.tournament_resources
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_resource public.tournament_resources;
begin
  select r.* into v_resource
  from public.tournament_resources r
  join public.tournaments t on t.id = r.tournament_id
  where r.id = p_resource_id
    and (t.owner_id = auth.uid() or public.is_admin(auth.uid()))
  for update of r;

  if v_resource.id is null then
    raise exception 'Resource not found or access denied';
  end if;

  update public.tournament_resources
  set tablet_name = nullif(trim(p_tablet_name),''),
      tablet_paired_at = now(),
      updated_at = now()
  where id = p_resource_id
  returning * into v_resource;

  return v_resource;
end;
$$;

grant execute on function public.get_station_tablet_state(uuid) to anon, authenticated;
grant execute on function public.confirm_station_player_presence(uuid, uuid) to anon, authenticated;
grant execute on function public.start_station_match(uuid) to anon, authenticated;
grant execute on function public.set_tournament_tablet_name(uuid, text) to authenticated;

