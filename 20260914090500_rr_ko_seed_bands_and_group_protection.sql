create unique index if not exists phase_qualifiers_phase_seed_unique_idx
  on public.phase_qualifiers(phase_id, seed)
  where seed is not null;

create or replace function public.complete_round_robin_phase(
  p_phase_id uuid,
  p_qualifiers jsonb,
  p_next_phase_type text
)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  ph public.tournament_phases;
  next_id uuid;
  q jsonb;
  next_num integer;
  normalized_next_type text;
  qualification_position_value integer;
  qualifier_seed integer;
  source_position_value integer;
  source_group_value integer;
  qualifier_metadata jsonb;
  source_group_count integer;
begin
  select p.* into ph
  from public.tournament_phases p
  join public.tournaments t on t.id = p.tournament_id
  where p.id = p_phase_id
    and (t.owner_id = auth.uid() or public.is_admin(auth.uid()))
  for update of p;

  if ph.id is null then raise exception 'Phase not found or access denied'; end if;
  if ph.phase_type not in ('rr','round_robin') then raise exception 'Phase is not round robin'; end if;

  normalized_next_type := case p_next_phase_type
    when 'sko' then 'sko'
    when 'single_elimination' then 'sko'
    when 'dko' then 'dko'
    when 'double_elimination' then 'dko'
    else null
  end;
  if normalized_next_type is null then raise exception 'Invalid next phase type'; end if;

  select p.id into next_id
  from public.tournament_phases p
  where p.tournament_id = ph.tournament_id
    and p.phase_type = normalized_next_type
    and p.config->>'source_phase_id' = p_phase_id::text
  order by p.phase_number
  limit 1;

  if next_id is not null then
    update public.tournaments set current_phase_id = next_id where id = ph.tournament_id;
    return next_id;
  end if;

  if exists(
    select 1 from public.matches
    where phase_id = p_phase_id
      and status not in ('completed','forfeited')
  ) then
    raise exception 'Phase contains unfinished matches';
  end if;

  delete from public.phase_qualifiers where phase_id = p_phase_id;

  for q in select * from jsonb_array_elements(coalesce(p_qualifiers,'[]'::jsonb)) loop
    if not exists(
      select 1 from public.tournament_players
      where id = (q->>'tournament_player_id')::uuid
        and tournament_id = ph.tournament_id
    ) then
      raise exception 'Invalid qualifier';
    end if;

    qualification_position_value := coalesce(
      nullif(q->>'qualification_position','')::integer,
      nullif(q->>'seed','')::integer,
      nullif(q->>'source_position','')::integer
    );
    qualifier_seed := coalesce(
      nullif(q->>'seed','')::integer,
      qualification_position_value
    );
    source_position_value := nullif(q->>'source_position','')::integer;
    source_group_value := nullif(q->>'source_group','')::integer;

    if qualification_position_value is null or qualification_position_value <= 0 then
      raise exception 'Invalid qualification position';
    end if;
    if qualifier_seed is null or qualifier_seed <= 0 then
      raise exception 'Invalid qualifier seed';
    end if;
    if source_position_value is not null and source_position_value <= 0 then
      raise exception 'Invalid source position';
    end if;
    if source_group_value is not null and source_group_value <= 0 then
      raise exception 'Invalid source group';
    end if;

    qualifier_metadata := coalesce(q->'metadata','{}'::jsonb);
    if source_position_value is not null then
      qualifier_metadata := qualifier_metadata || jsonb_build_object(
        'source_position', source_position_value,
        'seed_band', case
          when source_position_value = 1 then 'group_winner'
          when source_position_value = 2 then 'runner_up'
          else 'random_lower'
        end,
        'seeding_policy', 'rr_rank_bands_v1'
      );
    end if;

    insert into public.phase_qualifiers(
      phase_id,tournament_player_id,qualification_position,seed,source_group,metadata
    ) values(
      p_phase_id,
      (q->>'tournament_player_id')::uuid,
      qualification_position_value,
      qualifier_seed,
      source_group_value,
      qualifier_metadata
    );
  end loop;

  select count(distinct source_group)
    into source_group_count
  from public.phase_qualifiers
  where phase_id = p_phase_id
    and source_group is not null;

  if source_group_count > 0 then
    if exists(
      select 1 from public.phase_qualifiers
      where phase_id = p_phase_id
        and (metadata->>'source_position')::integer = 1
        and seed > source_group_count
    ) then
      raise exception 'Group winners must occupy the first seed band';
    end if;

    if exists(
      select 1 from public.phase_qualifiers
      where phase_id = p_phase_id
        and (metadata->>'source_position')::integer = 2
        and (seed <= source_group_count or seed > source_group_count * 2)
    ) then
      raise exception 'Second-place qualifiers must occupy the second seed band';
    end if;

    if exists(
      select 1 from public.phase_qualifiers
      where phase_id = p_phase_id
        and (metadata->>'source_position')::integer >= 3
        and seed <= source_group_count * 2
    ) then
      raise exception 'Lower qualifiers must be seeded after winners and runners-up';
    end if;
  end if;

  update public.tournament_phases
  set status='completed',completed_at=now()
  where id=p_phase_id;

  select coalesce(max(phase_number),0)+1 into next_num
  from public.tournament_phases
  where tournament_id=ph.tournament_id;

  insert into public.tournament_phases(
    tournament_id,phase_number,phase_type,status,config,started_at
  ) values(
    ph.tournament_id,next_num,normalized_next_type,'active',
    jsonb_build_object(
      'source_phase_id',p_phase_id,
      'seeding_policy','rr_rank_bands_v1',
      'group_winners_protected_first_round',true,
      'avoid_same_group_first_round',true,
      'lower_seed_draw','deterministic_random'
    ),now()
  ) returning id into next_id;

  update public.tournaments set current_phase_id=next_id where id=ph.tournament_id;

  insert into public.audit_logs(user_id,entity_type,entity_id,action,metadata)
  values(
    auth.uid(),'tournament_phase',p_phase_id,'completed',
    jsonb_build_object(
      'next_phase_id',next_id,
      'next_phase_type',normalized_next_type,
      'seeding_policy','rr_rank_bands_v1'
    )
  );

  return next_id;
end;
$function$;
