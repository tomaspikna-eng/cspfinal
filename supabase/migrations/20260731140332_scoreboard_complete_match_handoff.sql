create or replace function public.station_complete_match(
  p_token text,
  p_score1 integer,
  p_score2 integer
)
returns public.matches
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v public.matches;
  v_station_id uuid;
  v_winner_id uuid;
  v_add_seconds integer := 0;
begin
  if p_score1 is null or p_score2 is null or p_score1 < 0 or p_score2 < 0 then
    raise exception 'Score must be nonnegative';
  end if;

  if p_score1 = p_score2 then
    raise exception 'Completed match cannot end in a draw';
  end if;

  select s.id into v_station_id
  from public.stations s
  where s.token = p_token
    and s.is_active = true;

  if v_station_id is null then
    raise exception 'Invalid or inactive station token';
  end if;

  select m.* into v
  from public.matches m
  where m.station_id = v_station_id
    and m.status in ('ready','called','player_arriving','live','in_progress')
  order by
    case when m.status = 'in_progress' then 0 when m.status = 'live' then 1 else 2 end,
    m.updated_at desc
  limit 1
  for update;

  if v.id is null then
    raise exception 'No active match assigned to station';
  end if;

  if v.player1_id is null or v.player2_id is null then
    raise exception 'Match players are not assigned';
  end if;

  v_winner_id := case when p_score1 > p_score2 then v.player1_id else v.player2_id end;

  if v.match_clock_started_at is not null then
    v_add_seconds := greatest(extract(epoch from (now() - v.match_clock_started_at))::integer, 0);
  end if;

  update public.matches
  set score1 = p_score1,
      score2 = p_score2,
      winner_id = v_winner_id,
      status = 'completed',
      completed_at = now(),
      match_call_status = 'closed',
      match_clock_elapsed_seconds = match_clock_elapsed_seconds + v_add_seconds,
      match_clock_started_at = null,
      match_clock_paused_at = null,
      match_clock_stopped_at = now(),
      updated_at = now()
  where id = v.id
  returning * into v;

  insert into public.audit_logs(user_id, entity_type, entity_id, action, metadata)
  values (
    auth.uid(),
    'match',
    v.id,
    'scoreboard_completed',
    jsonb_build_object(
      'station_id', v_station_id,
      'score1', p_score1,
      'score2', p_score2,
      'winner_id', v_winner_id
    )
  );

  return v;
end;
$$;

grant execute on function public.station_complete_match(text, integer, integer) to anon, authenticated;

