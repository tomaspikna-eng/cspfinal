alter table public.matches add column if not exists race_to integer;

update public.matches m
set race_to = nullif(t.config->>'race_to','')::integer
from public.tournaments t
where t.id=m.tournament_id
  and m.race_to is null
  and nullif(t.config->>'race_to','') ~ '^[0-9]+$';

alter table public.matches drop constraint if exists matches_race_to_check;
alter table public.matches add constraint matches_race_to_check check (race_to is null or race_to > 0);

comment on column public.matches.race_to is 'Effective target/race-to for this specific match. Supports per-round tournament overrides.';

drop function if exists public.get_scoreboard_match(uuid,uuid);
create function public.get_scoreboard_match(p_match_id uuid, p_match_token uuid)
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
  race_to integer,
  match_status text,
  completed_at timestamptz
)
language sql
stable
security definer
set search_path to 'public','pg_temp'
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
    coalesce(m.score1,0),
    coalesce(m.score2,0),
    coalesce(m.race_to, nullif(t.config->>'race_to','')::integer, 5),
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
grant execute on function public.get_scoreboard_match(uuid,uuid) to anon, authenticated, service_role;

drop function if exists public.get_station_tablet_state(uuid);
create function public.get_station_tablet_state(p_device_token uuid)
returns table(
  resource_id uuid,
  tournament_id uuid,
  resource_number integer,
  resource_label text,
  resource_type text,
  resource_status text,
  tablet_name text,
  match_id uuid,
  match_token uuid,
  tournament_name text,
  sport text,
  discipline text,
  round_key text,
  match_number integer,
  race_to integer,
  player1_id uuid,
  player1_name text,
  player1_present boolean,
  player1_ready_at timestamptz,
  player2_id uuid,
  player2_name text,
  player2_present boolean,
  player2_ready_at timestamptz,
  both_players_present boolean,
  can_start boolean,
  score1 integer,
  score2 integer,
  match_status text,
  started_at timestamptz
)
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
begin
  update public.tournament_resources
  set tablet_last_seen_at=now(),
      tablet_paired_at=coalesce(tablet_paired_at,now()),
      updated_at=now()
  where device_token=p_device_token
    and is_active=true;

  return query
  select
    r.id,
    r.tournament_id,
    r.resource_number,
    r.label,
    r.resource_type,
    r.status,
    r.tablet_name,
    m.id,
    m.public_token,
    t.name,
    t.sport,
    t.discipline,
    m.round_key,
    m.match_number,
    coalesce(m.race_to, nullif(t.config->>'race_to','')::integer, 5),
    m.player1_id,
    p1.name,
    (m.player1_ready_at is not null),
    m.player1_ready_at,
    m.player2_id,
    p2.name,
    (m.player2_ready_at is not null),
    m.player2_ready_at,
    (m.player1_ready_at is not null and m.player2_ready_at is not null),
    (m.id is not null and m.player1_ready_at is not null and m.player2_ready_at is not null and m.started_at is null and m.status in ('called','player_arriving','ready')),
    coalesce(m.score1,0),
    coalesce(m.score2,0),
    m.status,
    m.started_at
  from public.tournament_resources r
  join public.tournaments t on t.id=r.tournament_id
  left join public.matches m on m.id=r.current_match_id
  left join public.tournament_players p1 on p1.id=m.player1_id
  left join public.tournament_players p2 on p2.id=m.player2_id
  where r.device_token=p_device_token
    and r.is_active=true;
end;
$$;
revoke all on function public.get_station_tablet_state(uuid) from public;
grant execute on function public.get_station_tablet_state(uuid) to anon, authenticated, service_role;
