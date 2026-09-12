create or replace function public.confirm_station_player_presence(p_device_token uuid, p_player_id uuid)
returns table(match_id uuid, player1_present boolean, player2_present boolean, both_players_present boolean, can_start boolean)
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
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
  if v_match.status in ('live','in_progress','completed','forfeited') then
    raise exception 'Presence can no longer be changed for this match';
  end if;

  -- Self-heal stale pre-start timestamps left by an older assignment/start flow.
  if v_match.started_at is not null then
    update public.matches
    set started_at = null,
        match_clock_started_at = null,
        match_clock_paused_at = null,
        match_clock_stopped_at = null,
        match_clock_elapsed_seconds = 0,
        updated_at = now()
    where id = v_match.id;
  end if;

  if p_player_id = v_match.player1_id then
    update public.matches
    set player1_ready_at = coalesce(player1_ready_at, now()),
        updated_at = now()
    where id = v_match.id;
  elsif p_player_id = v_match.player2_id then
    update public.matches
    set player2_ready_at = coalesce(player2_ready_at, now()),
        updated_at = now()
    where id = v_match.id;
  else
    raise exception 'Player does not belong to the assigned match';
  end if;

  update public.matches
  set status = case
        when player1_ready_at is not null and player2_ready_at is not null then 'ready'
        else 'player_arriving'
      end,
      match_call_status = 'arrival_window',
      updated_at = now()
  where id = v_match.id;

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
$function$;

create or replace function public.advance_round_robin_group_station()
returns trigger
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_map public.tournament_group_resources;
  v_resource public.tournament_resources;
  v_next public.matches;
  v_used_resource uuid;
begin
  if new.group_index is null then return new; end if;
  if new.status not in ('completed','forfeited') then return new; end if;
  if old.status in ('completed','forfeited') then return new; end if;

  select * into v_map
  from public.tournament_group_resources
  where tournament_id = new.tournament_id and group_index = new.group_index;

  if v_map.id is null then return new; end if;

  v_used_resource := coalesce(new.tournament_resource_id, old.tournament_resource_id);
  if v_used_resource is distinct from v_map.resource_id then return new; end if;

  select * into v_resource
  from public.tournament_resources
  where id = v_map.resource_id and is_active = true
  for update;

  if v_resource.id is null then return new; end if;
  if v_resource.current_match_id is not null and v_resource.current_match_id <> new.id then return new; end if;

  select m.* into v_next
  from public.matches m
  where m.tournament_id = new.tournament_id
    and m.group_index = new.group_index
    and m.id <> new.id
    and m.player1_id is not null
    and m.player2_id is not null
    and m.started_at is null
    and m.status in ('pending','waiting_for_table','ready','called','player_arriving')
  order by
    case
      when coalesce(m.round_number,2147483647) > coalesce(new.round_number,2147483647)
        or (coalesce(m.round_number,2147483647) = coalesce(new.round_number,2147483647)
            and coalesce(m.match_number,2147483647) > coalesce(new.match_number,2147483647))
      then 0 else 1
    end,
    m.round_number nulls last,
    m.match_number nulls last,
    m.created_at
  limit 1
  for update;

  if v_next.id is null then return new; end if;

  update public.tournament_resources
  set current_match_id = v_next.id,
      status = 'assigned',
      updated_at = now()
  where id = v_resource.id;

  update public.matches
  set tournament_resource_id = v_resource.id,
      tournament_resource_label = v_resource.label,
      player1_ready_at = null,
      player2_ready_at = null,
      started_at = null,
      completed_at = null,
      match_clock_elapsed_seconds = 0,
      match_clock_started_at = null,
      match_clock_paused_at = null,
      match_clock_stopped_at = null,
      status = 'ready',
      match_call_status = 'not_called',
      called_at = null,
      arrival_deadline_at = null,
      penalty_1_at = null,
      penalty_2_at = null,
      penalty_3_at = null,
      forfeit_at = null,
      updated_at = now()
  where id = v_next.id;

  insert into public.tournament_resource_assignments(tournament_id,resource_id,match_id,assigned_by,result_source)
  values(new.tournament_id,v_resource.id,v_next.id,auth.uid(),'system');

  return new;
end;
$function$;

-- Generic repair for currently assigned pre-start matches that carry stale start timestamps.
update public.matches m
set started_at = null,
    match_clock_started_at = null,
    match_clock_paused_at = null,
    match_clock_stopped_at = null,
    match_clock_elapsed_seconds = 0,
    updated_at = now()
where m.status in ('pending','waiting_for_table','ready','called','player_arriving')
  and m.started_at is not null
  and coalesce(m.score1,0) = 0
  and coalesce(m.score2,0) = 0
  and exists (
    select 1 from public.tournament_resources r
    where r.current_match_id = m.id and r.is_active = true
  );

