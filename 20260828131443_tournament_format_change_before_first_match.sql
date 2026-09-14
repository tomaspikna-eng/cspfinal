create or replace function public.reset_tournament_structure_for_format_change(
  p_tournament_id uuid,
  p_new_format text,
  p_groups_count integer default null,
  p_advance_count integer default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_t public.tournaments;
  v_started_count integer;
begin
  select * into v_t
  from public.tournaments
  where id = p_tournament_id
    and (owner_id = auth.uid() or public.is_admin(auth.uid()))
  for update;

  if v_t.id is null then
    raise exception 'Tournament not found or access denied';
  end if;

  if v_t.status not in ('draft','ready','active') then
    raise exception 'Tournament format can no longer be changed';
  end if;

  if p_new_format not in ('rr','sko','dko','rr_sko','rr_dko','karty') then
    raise exception 'Invalid tournament format';
  end if;

  select count(*) into v_started_count
  from public.matches m
  where m.tournament_id = p_tournament_id
    and (
      m.started_at is not null
      or m.completed_at is not null
      or m.winner_id is not null
      or coalesce(m.score1,0) <> 0
      or coalesce(m.score2,0) <> 0
      or m.status in ('live','in_progress','completed','forfeited','disputed')
      or exists(select 1 from public.score_events se where se.match_id = m.id and se.undone_at is null)
    );

  if v_started_count > 0 then
    raise exception 'Formát nie je možné zmeniť po začiatku prvého zápasu.';
  end if;

  update public.tournament_resources
  set current_match_id = null,
      status = 'available',
      updated_at = now()
  where tournament_id = p_tournament_id;

  delete from public.tournament_group_resources where tournament_id = p_tournament_id;
  delete from public.tournament_bracket_states where tournament_id = p_tournament_id;
  delete from public.tournament_groups where tournament_id = p_tournament_id;
  delete from public.tournament_results where tournament_id = p_tournament_id;
  delete from public.matches where tournament_id = p_tournament_id;

  update public.tournaments
  set current_phase_id = null,
      format = p_new_format,
      groups_count = case when p_new_format in ('rr_sko','rr_dko') then greatest(coalesce(p_groups_count,2),1) else null end,
      advance_count = case when p_new_format in ('rr_sko','rr_dko') then greatest(coalesce(p_advance_count,1),1) else null end,
      updated_at = now()
  where id = p_tournament_id;

  delete from public.tournament_phases where tournament_id = p_tournament_id;

  return jsonb_build_object(
    'tournament_id', p_tournament_id,
    'format', p_new_format,
    'groups_count', case when p_new_format in ('rr_sko','rr_dko') then greatest(coalesce(p_groups_count,2),1) else null end,
    'advance_count', case when p_new_format in ('rr_sko','rr_dko') then greatest(coalesce(p_advance_count,1),1) else null end,
    'structure_reset', true
  );
end;
$function$;

grant execute on function public.reset_tournament_structure_for_format_change(uuid,text,integer,integer) to authenticated;

