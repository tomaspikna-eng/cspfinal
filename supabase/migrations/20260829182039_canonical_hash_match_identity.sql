create or replace function public.canonicalize_tournament_match_identity(
  p_tournament_id uuid,
  p_mapping jsonb
)
returns integer
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_item jsonb;
  v_id uuid;
  v_number integer;
  v_ids uuid[] := array[]::uuid[];
  v_numbers integer[] := array[]::integer[];
  v_count integer := 0;
begin
  if not exists (
    select 1
    from public.tournaments t
    where t.id = p_tournament_id
      and (t.owner_id = auth.uid() or public.is_admin(auth.uid()))
  ) then
    raise exception 'Tournament not found or access denied';
  end if;

  if p_mapping is null or jsonb_typeof(p_mapping) <> 'array' then
    raise exception 'Mapping must be a JSON array';
  end if;

  -- Validate the full mapping before changing anything.
  for v_item in select value from jsonb_array_elements(p_mapping)
  loop
    begin
      v_id := (v_item->>'id')::uuid;
      v_number := (v_item->>'match_number')::integer;
    exception when others then
      raise exception 'Invalid match identity mapping';
    end;

    if v_number is null or v_number < 1 then
      raise exception 'Match number must be a positive integer';
    end if;
    if v_id = any(v_ids) then
      raise exception 'Duplicate match id in identity mapping';
    end if;
    if v_number = any(v_numbers) then
      raise exception 'Duplicate target match number in identity mapping';
    end if;
    if not exists (
      select 1 from public.matches m
      where m.id = v_id and m.tournament_id = p_tournament_id
    ) then
      raise exception 'Mapped match does not belong to tournament';
    end if;

    v_ids := array_append(v_ids, v_id);
    v_numbers := array_append(v_numbers, v_number);
  end loop;

  if coalesce(array_length(v_ids,1),0) = 0 then
    return 0;
  end if;

  -- A canonical #N owned by a row outside this migration would make the
  -- mapping ambiguous. Stop instead of guessing which row is authoritative.
  for v_item in select value from jsonb_array_elements(p_mapping)
  loop
    v_id := (v_item->>'id')::uuid;
    v_number := (v_item->>'match_number')::integer;
    if exists (
      select 1 from public.matches m
      where m.tournament_id = p_tournament_id
        and m.round_key = ('#' || v_number::text)
        and not (m.id = any(v_ids))
    ) then
      raise exception 'Canonical match #% already belongs to another row', v_number;
    end if;
  end loop;

  -- Two-pass rewrite prevents unique-key collisions when legacy rows are
  -- being renumbered. round_key becomes the one canonical bracket identity.
  for v_item in select value from jsonb_array_elements(p_mapping)
  loop
    v_id := (v_item->>'id')::uuid;
    v_number := (v_item->>'match_number')::integer;
    update public.matches
    set round_key = '__csp_match_tmp__:' || v_id::text,
        match_number = v_number,
        bracket_side = case
          when bracket_side = 'A' then 'W'
          when bracket_side = 'B' then 'L'
          else bracket_side
        end,
        updated_at = now()
    where id = v_id and tournament_id = p_tournament_id;
  end loop;

  for v_item in select value from jsonb_array_elements(p_mapping)
  loop
    v_id := (v_item->>'id')::uuid;
    v_number := (v_item->>'match_number')::integer;
    update public.matches
    set round_key = '#' || v_number::text,
        updated_at = now()
    where id = v_id and tournament_id = p_tournament_id;
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$function$;

grant execute on function public.canonicalize_tournament_match_identity(uuid,jsonb) to authenticated;

-- Enforce uniqueness for the new canonical identity without invalidating
-- legacy archived rows whose old engines reused local match_number values.
create unique index if not exists matches_tournament_canonical_match_number_uidx
  on public.matches(tournament_id, match_number)
  where match_number is not null
    and round_key = ('#' || match_number::text);

create or replace function public.complete_tournament(p_tournament_id uuid, p_results jsonb default '[]'::jsonb)
returns tournaments
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  t public.tournaments;
  r jsonb;
  was_completed boolean;
begin
  select * into t
  from public.tournaments
  where id=p_tournament_id
    and (owner_id=auth.uid() or public.is_admin(auth.uid()))
  for update;

  if t.id is null then
    raise exception 'Tournament not found or access denied';
  end if;

  was_completed := t.status='completed';

  if exists(
    select 1
    from public.matches m
    where m.tournament_id=p_tournament_id
      and m.status not in('completed','forfeited')
      and (
        t.format not in ('dko','rr_dko')
        or (
          t.format='dko'
          and (
            m.round_key ~ '^#[1-9][0-9]*$'
            or m.round_key like 'dkoA:%'
            or m.round_key like 'dkoB:%'
            or m.round_key like 'dkoS:%'
            or m.round_key like 'dkoF:%'
          )
        )
        or (
          t.format='rr_dko'
          and (
            m.round_key ~ '^#[1-9][0-9]*$'
            or m.round_key like 'grp:%'
            or m.round_key like 'p2dA:%'
            or m.round_key like 'p2dB:%'
            or m.round_key like 'p2dS:%'
            or m.round_key like 'p2dF:%'
          )
        )
      )
  ) then
    raise exception 'Tournament contains unfinished matches';
  end if;

  insert into public.tournament_results(
    tournament_id,tournament_player_id,user_id,matches_played,wins,losses,score_for,score_against
  )
  select
    p_tournament_id,
    tp.id,
    tp.user_id,
    count(m.id)::int,
    count(m.id) filter(where m.winner_id=tp.id)::int,
    count(m.id) filter(where m.id is not null and m.winner_id is distinct from tp.id)::int,
    coalesce(sum(case when m.player1_id=tp.id then coalesce(m.score1,0) when m.player2_id=tp.id then coalesce(m.score2,0) else 0 end),0)::int,
    coalesce(sum(case when m.player1_id=tp.id then coalesce(m.score2,0) when m.player2_id=tp.id then coalesce(m.score1,0) else 0 end),0)::int
  from public.tournament_players tp
  left join public.matches m
    on m.tournament_id=p_tournament_id
   and (m.player1_id=tp.id or m.player2_id=tp.id)
   and m.status in('completed','forfeited')
   and (
     t.format not in ('dko','rr_dko')
     or (
       t.format='dko'
       and (
         m.round_key ~ '^#[1-9][0-9]*$'
         or m.round_key like 'dkoA:%'
         or m.round_key like 'dkoB:%'
         or m.round_key like 'dkoS:%'
         or m.round_key like 'dkoF:%'
       )
     )
     or (
       t.format='rr_dko'
       and (
         m.round_key ~ '^#[1-9][0-9]*$'
         or m.round_key like 'grp:%'
         or m.round_key like 'p2dA:%'
         or m.round_key like 'p2dB:%'
         or m.round_key like 'p2dS:%'
         or m.round_key like 'p2dF:%'
       )
     )
   )
  where tp.tournament_id=p_tournament_id
  group by tp.id,tp.user_id
  on conflict(tournament_id,tournament_player_id) do update set
    user_id=excluded.user_id,
    matches_played=excluded.matches_played,
    wins=excluded.wins,
    losses=excluded.losses,
    score_for=excluded.score_for,
    score_against=excluded.score_against,
    updated_at=now();

  for r in select * from jsonb_array_elements(coalesce(p_results,'[]'::jsonb)) loop
    if not exists(
      select 1 from public.tournament_players
      where id=(r->>'tournament_player_id')::uuid
        and tournament_id=p_tournament_id
    ) then
      raise exception 'Invalid tournament_player_id in results';
    end if;

    update public.tournament_results
    set final_position=(r->>'final_position')::int,
        metadata=coalesce(r->'metadata','{}'::jsonb),
        updated_at=now()
    where tournament_id=p_tournament_id
      and tournament_player_id=(r->>'tournament_player_id')::uuid;
  end loop;

  update public.tournament_phases
  set status='completed',
      completed_at=coalesce(completed_at,now())
  where tournament_id=p_tournament_id
    and status<>'completed';

  update public.tournaments
  set status='completed',
      completed_at=coalesce(completed_at,now())
  where id=p_tournament_id
  returning * into t;

  if not was_completed then
    insert into public.audit_logs(user_id,entity_type,entity_id,action)
    values(auth.uid(),'tournament',p_tournament_id,'completed');
  end if;

  return t;
end;
$function$;

