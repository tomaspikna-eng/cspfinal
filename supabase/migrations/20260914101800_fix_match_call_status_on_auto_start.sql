create or replace function public.auto_start_match_when_both_ready()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.player1_ready_at is not null
     and new.player2_ready_at is not null
     and coalesce(new.status,'') not in ('in_progress','live','completed','forfeited','cancelled') then
    new.status := 'in_progress';
    new.started_at := coalesce(new.started_at, now());
    new.match_clock_started_at := coalesce(new.match_clock_started_at, now());
    new.match_call_status := 'closed';
  end if;
  return new;
end;
$$;

create or replace function public.scoreboard_set_player_ready(
  p_match_id uuid,
  p_match_token uuid,
  p_player_id uuid,
  p_active boolean
)
returns public.matches
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match public.matches;
begin
  select * into v_match
  from public.matches
  where id=p_match_id and public_token=p_match_token
  for update;

  if v_match.id is null then raise exception 'Match not found or invalid token'; end if;
  if v_match.status in ('completed','forfeited','cancelled') then raise exception 'Match is closed'; end if;

  if p_player_id=v_match.player1_id then
    update public.matches
    set player1_ready_at=case when p_active then now() else null end,
        updated_at=now()
    where id=p_match_id;
  elsif p_player_id=v_match.player2_id then
    update public.matches
    set player2_ready_at=case when p_active then now() else null end,
        updated_at=now()
    where id=p_match_id;
  else
    raise exception 'Player is not assigned to this match';
  end if;

  update public.matches
  set updated_at=now()
  where id=p_match_id;

  select * into v_match from public.matches where id=p_match_id;
  return v_match;
end;
$$;
