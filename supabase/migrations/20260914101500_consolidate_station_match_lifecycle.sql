create or replace function public.confirm_station_player_presence(p_device_token uuid, p_player_id uuid)
returns table(match_id uuid, player1_present boolean, player2_present boolean, both_players_present boolean, can_start boolean)
language plpgsql
security definer
set search_path = public
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
  if v_match.status in ('completed','forfeited','cancelled') then
    raise exception 'Match is already closed';
  end if;
  if v_match.status in ('in_progress','live') then
    return query
    select m.id,
           m.player1_ready_at is not null,
           m.player2_ready_at is not null,
           m.player1_ready_at is not null and m.player2_ready_at is not null,
           false
    from public.matches m where m.id=v_match.id;
    return;
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
        when player1_ready_at is not null and player2_ready_at is not null then status
        else 'player_arriving'
      end,
      match_call_status = case
        when player1_ready_at is not null and player2_ready_at is not null then match_call_status
        else 'arrival_window'
      end,
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
         false
  from public.matches m
  where m.id = v_match.id;
end;
$$;

revoke execute on function public.start_station_match(uuid) from anon, authenticated;

update public.matches
set started_at = null,
    match_clock_started_at = null,
    match_clock_paused_at = null,
    match_clock_stopped_at = null,
    match_clock_elapsed_seconds = 0,
    updated_at = now()
where status in ('pending','waiting_for_table','ready','called','player_arriving')
  and (player1_ready_at is null or player2_ready_at is null)
  and started_at is not null;
