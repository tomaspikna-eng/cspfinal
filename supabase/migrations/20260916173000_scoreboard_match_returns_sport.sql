-- A tournament scoreboard must receive the canonical tournament sport.
-- Discipline alone is ambiguous (for example "Singles" is used by both
-- tennis and table tennis) and previously made the client fall back to pool.

drop function if exists public.get_scoreboard_match(uuid,uuid);

create function public.get_scoreboard_match(
  p_match_id uuid,
  p_match_token uuid
)
returns table(
  match_id uuid,
  tournament_id uuid,
  tournament_name text,
  sport text,
  discipline text,
  round_key text,
  match_number integer,
  player1_id uuid,
  player1_name text,
  player2_id uuid,
  player2_name text,
  score1 integer,
  score2 integer,
  race_to integer,
  match_status text,
  completed_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    m.id,
    m.tournament_id,
    t.name,
    t.sport,
    t.discipline,
    m.round_key,
    m.match_number,
    m.player1_id,
    p1.name,
    m.player2_id,
    p2.name,
    coalesce(m.score1,0),
    coalesce(m.score2,0),
    coalesce(m.race_to,nullif(t.config->>'race_to','')::integer,5),
    m.status,
    m.completed_at
  from public.matches m
  join public.tournaments t on t.id=m.tournament_id
  left join public.tournament_players p1 on p1.id=m.player1_id
  left join public.tournament_players p2 on p2.id=m.player2_id
  where m.id=p_match_id
    and m.public_token=p_match_token;
$$;

revoke all on function public.get_scoreboard_match(uuid,uuid) from public;
grant execute on function public.get_scoreboard_match(uuid,uuid) to anon,authenticated,service_role;

