create or replace function public.complete_round_robin_phase(
  p_phase_id uuid,
  p_qualifiers jsonb,
  p_next_phase_type text
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  ph public.tournament_phases;
  next_id uuid;
  q jsonb;
  next_num integer;
  normalized_next_type text;
  qualification_position_value integer;
  qualifier_metadata jsonb;
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

  -- Idempotency: if this RR phase was already transitioned, reuse that phase.
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

    -- qualification_position must be globally unique inside the phase.
    -- `source_position` repeats between groups (A1, B1, ...), while `seed`
    -- is the global cross-seeded order used by the knockout bracket.
    qualification_position_value := coalesce(
      nullif(q->>'seed','')::integer,
      nullif(q->>'qualification_position','')::integer,
      nullif(q->>'source_position','')::integer
    );

    if qualification_position_value is null or qualification_position_value <= 0 then
      raise exception 'Invalid qualification position';
    end if;

    qualifier_metadata := coalesce(q->'metadata','{}'::jsonb);
    if nullif(q->>'source_position','') is not null then
      qualifier_metadata := qualifier_metadata || jsonb_build_object(
        'source_position', (q->>'source_position')::integer
      );
    end if;

    insert into public.phase_qualifiers(
      phase_id,tournament_player_id,qualification_position,seed,source_group,metadata
    ) values(
      p_phase_id,
      (q->>'tournament_player_id')::uuid,
      qualification_position_value,
      coalesce(nullif(q->>'seed','')::integer,qualification_position_value),
      nullif(q->>'source_group','')::integer,
      qualifier_metadata
    );
  end loop;

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
    jsonb_build_object('source_phase_id',p_phase_id),now()
  ) returning id into next_id;

  update public.tournaments set current_phase_id=next_id where id=ph.tournament_id;

  insert into public.audit_logs(user_id,entity_type,entity_id,action,metadata)
  values(
    auth.uid(),'tournament_phase',p_phase_id,'completed',
    jsonb_build_object('next_phase_id',next_id,'next_phase_type',normalized_next_type)
  );

  return next_id;
end;
$$;

revoke execute on function public.complete_round_robin_phase(uuid,jsonb,text) from public,anon;
grant execute on function public.complete_round_robin_phase(uuid,jsonb,text) to authenticated,service_role;

