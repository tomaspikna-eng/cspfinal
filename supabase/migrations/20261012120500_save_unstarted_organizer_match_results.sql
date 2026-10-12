create or replace function public.save_organizer_match_result(
  p_tournament_id uuid,
  p_phase_id uuid,
  p_round_key text,
  p_round_number integer,
  p_match_number integer,
  p_group_index integer,
  p_bracket_side text,
  p_player1_id uuid,
  p_player2_id uuid,
  p_score1 integer,
  p_score2 integer,
  p_winner_id uuid,
  p_race_to integer,
  p_race_to_key text
)
returns public.matches
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_match public.matches;
  v_resource_id uuid;
  v_final_elapsed integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if p_tournament_id is null or coalesce(trim(p_round_key),'')='' or p_match_number is null then
    raise exception 'Tournament, round key and match number are required';
  end if;
  if p_player1_id is null or p_player2_id is null then
    raise exception 'Match does not have both players';
  end if;
  if p_score1 is null or p_score2 is null or p_score1 < 0 or p_score2 < 0 then
    raise exception 'Scores must be nonnegative';
  end if;
  if p_score1 = p_score2 then
    raise exception 'Match score cannot be tied';
  end if;
  if p_winner_id is distinct from p_player1_id and p_winner_id is distinct from p_player2_id then
    raise exception 'Winner must be one of the match players';
  end if;

  if not exists (
    select 1 from public.tournaments t
    where t.id=p_tournament_id
      and (t.owner_id=auth.uid() or public.is_admin(auth.uid()))
  ) then
    raise exception 'Tournament not found or access denied';
  end if;

  if exists (
    select 1
    from (values (p_player1_id),(p_player2_id),(p_winner_id)) v(id)
    where v.id is not null
      and not exists (
        select 1 from public.tournament_players tp
        where tp.id=v.id and tp.tournament_id=p_tournament_id
      )
  ) then
    raise exception 'Player does not belong to tournament';
  end if;

  select m.* into v_match
  from public.matches m
  where m.tournament_id=p_tournament_id and m.round_key=p_round_key
  for update;

  if v_match.id is not null then
    v_resource_id:=v_match.tournament_resource_id;
    v_final_elapsed:=coalesce(v_match.match_clock_elapsed_seconds,0);

    if v_match.match_clock_started_at is not null
       and v_match.match_clock_paused_at is null
       and v_match.status in ('live','in_progress') then
      v_final_elapsed:=v_final_elapsed + greatest(
        0,
        floor(extract(epoch from (now()-v_match.match_clock_started_at)))::integer
      );
    end if;

    update public.matches
    set phase_id=p_phase_id,
        round_number=p_round_number,
        match_number=p_match_number,
        group_index=p_group_index,
        bracket_side=p_bracket_side,
        player1_id=p_player1_id,
        player2_id=p_player2_id,
        score1=p_score1,
        score2=p_score2,
        winner_id=p_winner_id,
        status='completed',
        completed_at=coalesce(completed_at,now()),
        match_call_status='closed',
        match_clock_elapsed_seconds=v_final_elapsed,
        match_clock_started_at=null,
        match_clock_paused_at=null,
        match_clock_stopped_at=coalesce(match_clock_stopped_at,now()),
        result_source='organizer',
        result_submitted_at=now(),
        race_to=coalesce(p_race_to,race_to),
        race_to_key=coalesce(p_race_to_key,race_to_key),
        tournament_resource_id=null,
        updated_at=now()
    where id=v_match.id
    returning * into v_match;

    update public.tournament_resource_assignments
    set completed_at=coalesce(completed_at,now()),
        released_at=coalesce(released_at,now()),
        score1=p_score1,
        score2=p_score2,
        winner_id=p_winner_id,
        result_source='organizer'
    where match_id=v_match.id and released_at is null;

    if v_resource_id is not null then
      update public.tournament_resources
      set current_match_id=null,status='available',updated_at=now()
      where id=v_resource_id and current_match_id=v_match.id;
    end if;
  else
    insert into public.matches(
      tournament_id,phase_id,round_key,round_number,match_number,group_index,bracket_side,
      player1_id,player2_id,score1,score2,winner_id,status,
      completed_at,match_call_status,match_clock_elapsed_seconds,
      match_clock_started_at,match_clock_paused_at,match_clock_stopped_at,
      result_source,result_submitted_at,race_to,race_to_key
    )
    values(
      p_tournament_id,p_phase_id,p_round_key,p_round_number,p_match_number,p_group_index,p_bracket_side,
      p_player1_id,p_player2_id,p_score1,p_score2,p_winner_id,'completed',
      now(),'closed',0,
      null,null,now(),
      'organizer',now(),p_race_to,p_race_to_key
    )
    returning * into v_match;
  end if;

  return v_match;
end;
$function$;

revoke all on function public.save_organizer_match_result(
  uuid,uuid,text,integer,integer,integer,text,uuid,uuid,integer,integer,uuid,integer,text
) from public;

grant execute on function public.save_organizer_match_result(
  uuid,uuid,text,integer,integer,integer,text,uuid,uuid,integer,integer,uuid,integer,text
) to authenticated;
