create or replace function public.complete_tournament(p_tournament_id uuid, p_results jsonb default '[]'::jsonb)
returns public.tournaments
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
    select 1 from public.matches
    where tournament_id=p_tournament_id
      and status not in('completed','forfeited')
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

