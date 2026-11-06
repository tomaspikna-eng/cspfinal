alter table public.matches
  add column if not exists pairing_manual_override boolean not null default false;

create or replace function public.override_tournament_match_pairings(
  p_tournament_id uuid,
  p_assignments jsonb
)
returns setof public.matches
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_item jsonb;
  v_match public.matches;
  v_match_id uuid;
  v_player1_id uuid;
  v_player2_id uuid;
  v_ids uuid[] := '{}'::uuid[];
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_tournament_id is null then
    raise exception 'Tournament is required';
  end if;

  if not exists (
    select 1 from public.tournaments t
    where t.id = p_tournament_id
      and (t.owner_id = auth.uid() or public.is_admin(auth.uid()))
  ) then
    raise exception 'Tournament not found or access denied';
  end if;

  if jsonb_typeof(p_assignments) <> 'array' or jsonb_array_length(p_assignments) < 1 then
    raise exception 'At least one pairing assignment is required';
  end if;

  if jsonb_array_length(p_assignments) > 64 then
    raise exception 'Too many pairing assignments';
  end if;

  if exists (
    with parsed as (
      select
        nullif(x->>'match_id','')::uuid as match_id,
        nullif(x->>'player1_id','')::uuid as player1_id,
        nullif(x->>'player2_id','')::uuid as player2_id
      from jsonb_array_elements(p_assignments) x
    ),
    players as (
      select player1_id as player_id from parsed
      union all
      select player2_id from parsed
    )
    select 1
    from players
    where player_id is not null
    group by player_id
    having count(*) > 1
  ) then
    raise exception 'A player cannot appear in more than one edited match';
  end if;

  for v_item in select value from jsonb_array_elements(p_assignments)
  loop
    v_match_id := nullif(v_item->>'match_id','')::uuid;
    v_player1_id := nullif(v_item->>'player1_id','')::uuid;
    v_player2_id := nullif(v_item->>'player2_id','')::uuid;

    if v_match_id is null or v_player1_id is null or v_player2_id is null then
      raise exception 'Match and both players are required';
    end if;

    if v_player1_id = v_player2_id then
      raise exception 'Players in a match must be different';
    end if;

    if exists (
      select 1
      from (values (v_player1_id),(v_player2_id)) p(id)
      where not exists (
        select 1 from public.tournament_players tp
        where tp.id = p.id and tp.tournament_id = p_tournament_id
      )
    ) then
      raise exception 'Player does not belong to tournament';
    end if;

    select m.* into v_match
    from public.matches m
    where m.id = v_match_id
      and m.tournament_id = p_tournament_id
    for update;

    if v_match.id is null then
      raise exception 'Match not found';
    end if;

    if v_match.started_at is not null
       or v_match.completed_at is not null
       or v_match.winner_id is not null
       or coalesce(v_match.score1,0) <> 0
       or coalesce(v_match.score2,0) <> 0
       or v_match.status in ('live','in_progress','completed','forfeited','disputed') then
      raise exception 'Started or completed match cannot be re-paired';
    end if;

    update public.matches
    set player1_id = v_player1_id,
        player2_id = v_player2_id,
        pairing_manual_override = true,
        score1 = null,
        score2 = null,
        winner_id = null,
        status = 'pending',
        completed_at = null,
        player1_reported_score = null,
        player1_reported_at = null,
        player2_reported_score = null,
        player2_reported_at = null,
        player1_ready_at = null,
        player2_ready_at = null,
        called_at = null,
        arrival_deadline_at = null,
        penalty_1_at = null,
        penalty_2_at = null,
        penalty_3_at = null,
        forfeit_at = null,
        late_player_id = null,
        penalty_score_awarded = 0,
        forfeit_reason = null,
        match_call_status = 'not_called',
        result_source = null,
        result_submitted_at = null,
        updated_at = now()
    where id = v_match_id;

    v_ids := array_append(v_ids, v_match_id);
  end loop;

  return query
  select m.*
  from public.matches m
  where m.id = any(v_ids)
  order by m.match_number;
end;
$$;

revoke all on function public.override_tournament_match_pairings(uuid,jsonb) from public, anon;
grant execute on function public.override_tournament_match_pairings(uuid,jsonb) to authenticated;
