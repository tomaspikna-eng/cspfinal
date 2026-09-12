-- Make IHS deterministic when an organizer corrects or clears a result.
-- A changed historical result can affect later opponent-strength calculations,
-- so rebuild the affected sport chronologically instead of trying to reverse one delta.

create or replace function public.rebuild_ihs_sport(p_sport text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_key text := public.normalize_ihs_sport(p_sport);
  rec record;
  v_r1 public.player_ihs_ratings;
  v_r2 public.player_ihs_ratings;
  v_before1 numeric(4,2);
  v_before2 numeric(4,2);
  v_after1 numeric(4,2);
  v_after2 numeric(4,2);
  v_expected1 numeric;
  v_score1 numeric;
  v_delta numeric;
  v_k numeric(4,2);
begin
  if v_key is null then return; end if;

  delete from public.ihs_rating_events where sport_key = v_key;

  update public.player_ihs_ratings r
  set rating = coalesce(ip.default_rating, 2.50),
      verified_matches = 0,
      wins = 0,
      losses = 0,
      last_match_at = null,
      updated_at = now()
  from public.player_ihs_profiles ip
  where r.player_id = ip.player_id
    and r.sport_key = v_key;

  for rec in
    select
      m.id as match_id,
      m.tournament_id,
      t.sport,
      coalesce(p1.user_id, pi1.claimed_profile_id) as player1_profile_id,
      coalesce(p2.user_id, pi2.claimed_profile_id) as player2_profile_id,
      case
        when m.winner_id = m.player1_id then coalesce(p1.user_id, pi1.claimed_profile_id)
        when m.winner_id = m.player2_id then coalesce(p2.user_id, pi2.claimed_profile_id)
        else null
      end as winner_profile_id,
      coalesce(m.completed_at, m.updated_at, m.created_at) as played_at
    from public.matches m
    join public.tournaments t on t.id = m.tournament_id
    join public.tournament_players p1 on p1.id = m.player1_id
    join public.tournament_players p2 on p2.id = m.player2_id
    left join public.player_identities pi1 on pi1.id = p1.player_identity_id and pi1.status = 'claimed'
    left join public.player_identities pi2 on pi2.id = p2.player_identity_id and pi2.status = 'claimed'
    where m.status = 'completed'
      and m.winner_id is not null
      and public.normalize_ihs_sport(t.sport) = v_key
      and coalesce(p1.user_id, pi1.claimed_profile_id) is not null
      and coalesce(p2.user_id, pi2.claimed_profile_id) is not null
      and coalesce(p1.user_id, pi1.claimed_profile_id) <> coalesce(p2.user_id, pi2.claimed_profile_id)
    order by coalesce(m.completed_at, m.updated_at, m.created_at), m.created_at, m.id
  loop
    if rec.winner_profile_id is null then continue; end if;

    v_r1 := public.ensure_player_ihs_rating(rec.player1_profile_id, rec.sport);
    v_r2 := public.ensure_player_ihs_rating(rec.player2_profile_id, rec.sport);
    v_before1 := v_r1.rating;
    v_before2 := v_r2.rating;
    v_score1 := case when rec.winner_profile_id = rec.player1_profile_id then 1 else 0 end;
    v_k := case when least(v_r1.verified_matches, v_r2.verified_matches) < 10 then 0.60 else 0.35 end;
    v_expected1 := 1.0 / (1.0 + power(10.0, (v_before2 - v_before1) / 2.0));
    v_delta := v_k * (v_score1 - v_expected1);
    v_after1 := round(greatest(1.00, least(10.00, v_before1 + v_delta))::numeric, 2);
    v_after2 := round(greatest(1.00, least(10.00, v_before2 - v_delta))::numeric, 2);

    update public.player_ihs_ratings
    set rating = v_after1,
        verified_matches = verified_matches + 1,
        wins = wins + case when rec.winner_profile_id = rec.player1_profile_id then 1 else 0 end,
        losses = losses + case when rec.winner_profile_id = rec.player2_profile_id then 1 else 0 end,
        last_match_at = rec.played_at,
        updated_at = now()
    where player_id = rec.player1_profile_id and sport_key = v_key;

    update public.player_ihs_ratings
    set rating = v_after2,
        verified_matches = verified_matches + 1,
        wins = wins + case when rec.winner_profile_id = rec.player2_profile_id then 1 else 0 end,
        losses = losses + case when rec.winner_profile_id = rec.player1_profile_id then 1 else 0 end,
        last_match_at = rec.played_at,
        updated_at = now()
    where player_id = rec.player2_profile_id and sport_key = v_key;

    insert into public.ihs_rating_events(
      match_id, tournament_id, sport_key, player1_id, player2_id, winner_id,
      player1_rating_before, player1_rating_after,
      player2_rating_before, player2_rating_after, k_factor, created_at
    ) values (
      rec.match_id, rec.tournament_id, v_key,
      rec.player1_profile_id, rec.player2_profile_id, rec.winner_profile_id,
      v_before1, v_after1, v_before2, v_after2, v_k, rec.played_at
    );
  end loop;
end;
$$;

create or replace function public.process_verified_match_ihs()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_sport text;
begin
  select sport into v_sport
  from public.tournaments
  where id = coalesce(new.tournament_id, old.tournament_id);

  if v_sport is not null then
    perform public.rebuild_ihs_sport(v_sport);
  end if;

  return new;
end;
$$;

-- Rebuild any currently known rating sports once under the deterministic engine.
do $$
declare r record;
begin
  for r in select distinct sport from public.tournaments where sport is not null loop
    perform public.rebuild_ihs_sport(r.sport);
  end loop;
end;
$$;

