begin;

create or replace function public.set_organizer_match_result(
  p_match_id uuid,
  p_score1 integer,
  p_score2 integer,
  p_winner_id uuid
) returns public.matches
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_match public.matches;
  v_resource_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if p_match_id is null then
    raise exception 'Match id is required';
  end if;
  if p_score1 is null or p_score2 is null or p_score1 < 0 or p_score2 < 0 then
    raise exception 'Scores must be nonnegative';
  end if;
  if p_score1 = p_score2 then
    raise exception 'Match score cannot be tied';
  end if;

  select m.* into v_match
  from public.matches m
  join public.tournaments t on t.id=m.tournament_id
  where m.id=p_match_id
    and (t.owner_id=auth.uid() or public.is_admin(auth.uid()))
  for update of m;

  if v_match.id is null then
    raise exception 'Match not found or access denied';
  end if;
  if v_match.player1_id is null or v_match.player2_id is null then
    raise exception 'Match does not have both players';
  end if;
  if p_winner_id is distinct from v_match.player1_id
     and p_winner_id is distinct from v_match.player2_id then
    raise exception 'Winner must be one of the match players';
  end if;

  v_resource_id:=v_match.tournament_resource_id;

  update public.matches
  set score1=p_score1,
      score2=p_score2,
      winner_id=p_winner_id,
      status='completed',
      completed_at=coalesce(completed_at,now()),
      match_call_status='closed',
      match_clock_started_at=null,
      match_clock_paused_at=null,
      match_clock_stopped_at=coalesce(match_clock_stopped_at,now()),
      result_source='organizer',
      result_submitted_at=now(),
      tournament_resource_id=null,
      updated_at=now()
  where id=p_match_id
  returning * into v_match;

  update public.tournament_resource_assignments
  set completed_at=coalesce(completed_at,now()),
      released_at=coalesce(released_at,now()),
      score1=p_score1,
      score2=p_score2,
      winner_id=p_winner_id,
      result_source='organizer'
  where match_id=p_match_id and released_at is null;

  if v_resource_id is not null then
    update public.tournament_resources
    set current_match_id=null,status='available',updated_at=now()
    where id=v_resource_id and current_match_id=p_match_id;
  end if;

  return v_match;
end;
$function$;

create or replace function public.reopen_organizer_match(
  p_match_id uuid
) returns public.matches
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_match public.matches;
  v_resource_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select m.* into v_match
  from public.matches m
  join public.tournaments t on t.id=m.tournament_id
  where m.id=p_match_id
    and (t.owner_id=auth.uid() or public.is_admin(auth.uid()))
  for update of m;

  if v_match.id is null then
    raise exception 'Match not found or access denied';
  end if;

  v_resource_id:=v_match.tournament_resource_id;

  update public.matches
  set score1=null,
      score2=null,
      winner_id=null,
      status='pending',
      completed_at=null,
      player1_reported_score=null,
      player1_reported_at=null,
      player2_reported_score=null,
      player2_reported_at=null,
      match_call_status='pending',
      result_source=null,
      result_submitted_at=null,
      tournament_resource_id=null,
      started_at=null,
      called_at=null,
      match_clock_elapsed_seconds=0,
      match_clock_started_at=null,
      match_clock_paused_at=null,
      match_clock_stopped_at=null,
      updated_at=now()
  where id=p_match_id
  returning * into v_match;

  update public.tournament_resource_assignments
  set released_at=coalesce(released_at,now())
  where match_id=p_match_id and released_at is null;

  if v_resource_id is not null then
    update public.tournament_resources
    set current_match_id=null,status='available',updated_at=now()
    where id=v_resource_id and current_match_id=p_match_id;
  end if;

  return v_match;
end;
$function$;

revoke all on function public.set_organizer_match_result(uuid,integer,integer,uuid) from public;
grant execute on function public.set_organizer_match_result(uuid,integer,integer,uuid) to authenticated, service_role;
revoke all on function public.reopen_organizer_match(uuid) from public;
grant execute on function public.reopen_organizer_match(uuid) to authenticated, service_role;

commit;
