create or replace function public.complete_scoreboard_match(
  p_match_id uuid,
  p_match_token uuid,
  p_score1 integer,
  p_score2 integer,
  p_winner_id uuid
)
returns public.matches
language plpgsql
security definer
set search_path to public, pg_temp
as $$
declare
  v_match public.matches;
  v_elapsed integer;
begin
  if p_match_id is null or p_match_token is null then
    raise exception 'Match id and match token are required';
  end if;

  if p_score1 is null or p_score2 is null or p_score1 < 0 or p_score2 < 0 then
    raise exception 'Scores must be nonnegative';
  end if;

  select m.*
    into v_match
  from public.matches m
  where m.id = p_match_id
    and m.public_token = p_match_token
  for update;

  if v_match.id is null then
    raise exception 'Match not found or invalid match token';
  end if;

  if v_match.player1_id is null or v_match.player2_id is null then
    raise exception 'Match does not have both players';
  end if;

  if v_match.status in ('completed','forfeited','cancelled') then
    raise exception 'Match is already closed';
  end if;

  if p_winner_id is distinct from v_match.player1_id
     and p_winner_id is distinct from v_match.player2_id then
    raise exception 'Winner must be one of the match players';
  end if;

  v_elapsed := coalesce(v_match.match_clock_elapsed_seconds, 0)
    + case
        when v_match.match_clock_started_at is not null
          then greatest(extract(epoch from (now() - v_match.match_clock_started_at))::integer, 0)
        else 0
      end;

  update public.matches
  set score1 = p_score1,
      score2 = p_score2,
      winner_id = p_winner_id,
      status = 'completed',
      completed_at = now(),
      match_call_status = 'closed',
      match_clock_elapsed_seconds = v_elapsed,
      match_clock_started_at = null,
      match_clock_paused_at = null,
      match_clock_stopped_at = now(),
      result_source = 'scoreboard',
      result_submitted_at = now(),
      updated_at = now()
  where id = p_match_id
  returning * into v_match;

  update public.tournament_resource_assignments
  set completed_at = coalesce(completed_at, now()),
      released_at = coalesce(released_at, now()),
      score1 = p_score1,
      score2 = p_score2,
      winner_id = p_winner_id,
      result_source = 'scoreboard'
  where match_id = p_match_id
    and released_at is null;

  update public.tournament_resources
  set current_match_id = null,
      status = 'available',
      updated_at = now()
  where current_match_id = p_match_id;

  update public.matches
  set tournament_resource_id = null
  where id = p_match_id;

  return v_match;
end;
$$;

revoke all on function public.complete_scoreboard_match(uuid, uuid, integer, integer, uuid) from public;
grant execute on function public.complete_scoreboard_match(uuid, uuid, integer, integer, uuid) to anon, authenticated;

create or replace function public.get_scoreboard_match(
  p_match_id uuid,
  p_match_token uuid
)
returns table(
  match_id uuid,
  tournament_id uuid,
  tournament_name text,
  discipline text,
  round_key text,
  match_number integer,
  player1_id uuid,
  player1_name text,
  player2_id uuid,
  player2_name text,
  score1 integer,
  score2 integer,
  match_status text,
  completed_at timestamptz
)
language sql
stable
security definer
set search_path to public, pg_temp
as $$
  select
    m.id,
    m.tournament_id,
    t.name,
    t.discipline,
    m.round_key,
    m.match_number,
    m.player1_id,
    p1.name,
    m.player2_id,
    p2.name,
    coalesce(m.score1, 0),
    coalesce(m.score2, 0),
    m.status,
    m.completed_at
  from public.matches m
  join public.tournaments t on t.id = m.tournament_id
  left join public.tournament_players p1 on p1.id = m.player1_id
  left join public.tournament_players p2 on p2.id = m.player2_id
  where m.id = p_match_id
    and m.public_token = p_match_token;
$$;

revoke all on function public.get_scoreboard_match(uuid, uuid) from public;
grant execute on function public.get_scoreboard_match(uuid, uuid) to anon, authenticated;

