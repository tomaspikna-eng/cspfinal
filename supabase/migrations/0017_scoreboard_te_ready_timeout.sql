-- Scoreboard TE: player readiness, automatic start and live time-out state.
alter table public.matches
  add column if not exists player1_timeout_active boolean not null default false,
  add column if not exists player2_timeout_active boolean not null default false,
  add column if not exists player1_timeout_at timestamptz,
  add column if not exists player2_timeout_at timestamptz;

create or replace function public.scoreboard_set_player_ready(
  p_match_id uuid,
  p_match_token uuid,
  p_player_id uuid,
  p_active boolean
) returns public.matches
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_match public.matches;
begin
  select * into v_match from public.matches
  where id=p_match_id and public_token=p_match_token for update;
  if v_match.id is null then raise exception 'Match not found or invalid token'; end if;
  if v_match.status in ('completed','forfeited','cancelled') then raise exception 'Match is closed'; end if;
  if p_player_id=v_match.player1_id then
    update public.matches set player1_ready_at=case when p_active then now() else null end,updated_at=now() where id=p_match_id;
  elsif p_player_id=v_match.player2_id then
    update public.matches set player2_ready_at=case when p_active then now() else null end,updated_at=now() where id=p_match_id;
  else raise exception 'Player is not assigned to this match';
  end if;
  update public.matches
  set status='in_progress',started_at=coalesce(started_at,now()),match_call_status='playing',
      match_clock_started_at=coalesce(match_clock_started_at,now()),updated_at=now()
  where id=p_match_id and player1_ready_at is not null and player2_ready_at is not null
    and status not in ('in_progress','live');
  select * into v_match from public.matches where id=p_match_id;
  return v_match;
end;
$$;

create or replace function public.scoreboard_set_player_timeout(
  p_match_id uuid,
  p_match_token uuid,
  p_player_id uuid,
  p_active boolean
) returns public.matches
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_match public.matches;
begin
  select * into v_match from public.matches
  where id=p_match_id and public_token=p_match_token for update;
  if v_match.id is null then raise exception 'Match not found or invalid token'; end if;
  if v_match.status not in ('in_progress','live') then raise exception 'Match is not running'; end if;
  if p_player_id=v_match.player1_id then
    update public.matches set player1_timeout_active=p_active,
      player1_timeout_at=case when p_active then now() else player1_timeout_at end,updated_at=now() where id=p_match_id;
  elsif p_player_id=v_match.player2_id then
    update public.matches set player2_timeout_active=p_active,
      player2_timeout_at=case when p_active then now() else player2_timeout_at end,updated_at=now() where id=p_match_id;
  else raise exception 'Player is not assigned to this match';
  end if;
  select * into v_match from public.matches where id=p_match_id;
  return v_match;
end;
$$;

revoke all on function public.scoreboard_set_player_ready(uuid,uuid,uuid,boolean) from public;
revoke all on function public.scoreboard_set_player_timeout(uuid,uuid,uuid,boolean) from public;
grant execute on function public.scoreboard_set_player_ready(uuid,uuid,uuid,boolean) to anon,authenticated;
grant execute on function public.scoreboard_set_player_timeout(uuid,uuid,uuid,boolean) to anon,authenticated;
