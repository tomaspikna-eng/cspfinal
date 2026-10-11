begin;

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
      match_call_status='not_called',
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

revoke all on function public.reopen_organizer_match(uuid) from public;
grant execute on function public.reopen_organizer_match(uuid) to authenticated, service_role;

commit;
