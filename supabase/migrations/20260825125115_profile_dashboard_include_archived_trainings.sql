create or replace function public.get_my_player_profile_dashboard()
returns jsonb
language sql
stable
set search_path to ''
as $function$
  with me as (
    select
      p.id,
      p.full_name,
      p.role::text as role,
      public.current_plan(p.id) as plan,
      p.avatar_url,
      p.cover_url,
      p.bio,
      p.created_at
    from public.profiles p
    where p.id = (select auth.uid())
  ),
  range_start as (
    select now() - interval '30 days' as at
  ),
  recent_training as (
    select
      ts.*,
      coalesce(
        nullif(ts.duration_seconds,0),
        nullif(ts.elapsed_seconds,0),
        case
          when ts.started_at is not null and ts.archived_at is not null
            then greatest(extract(epoch from (ts.archived_at-ts.started_at))::bigint,0)
          else 0
        end
      ) as effective_duration_seconds,
      coalesce(ts.completed_at, ts.archived_at, ts.played_at, ts.updated_at, ts.created_at) as occurred_at
    from public.training_sessions ts, range_start r
    where ts.owner_id = (select id from me)
      and ts.status in ('completed','archived')
      and coalesce(ts.completed_at, ts.archived_at, ts.played_at, ts.updated_at, ts.created_at) >= r.at
  ),
  my_tournament_players as (
    select tp.id, tp.tournament_id
    from public.tournament_players tp
    where tp.user_id = (select id from me)
  ),
  recent_matches as (
    select
      m.id,
      m.tournament_id,
      t.name as tournament_name,
      t.sport,
      t.discipline,
      mine.id as my_player_id,
      opponent.name as opponent_name,
      case when m.player1_id = mine.id then m.score1 else m.score2 end as my_score,
      case when m.player1_id = mine.id then m.score2 else m.score1 end as opponent_score,
      case
        when m.winner_id = mine.id then 'win'
        when m.winner_id is null then 'unknown'
        else 'loss'
      end as result,
      m.match_clock_elapsed_seconds as duration_seconds,
      coalesce(m.completed_at, m.started_at, m.scheduled_at, m.created_at) as occurred_at
    from my_tournament_players mine
    join public.matches m
      on m.player1_id = mine.id or m.player2_id = mine.id
    join public.tournaments t on t.id = m.tournament_id
    left join public.tournament_players opponent
      on opponent.id = case when m.player1_id = mine.id then m.player2_id else m.player1_id end
    cross join range_start r
    where m.status in ('completed', 'forfeited')
      and coalesce(m.completed_at, m.started_at, m.scheduled_at, m.created_at) >= r.at
  ),
  training_summary as (
    select
      count(*)::integer as completed_count,
      coalesce(sum(effective_duration_seconds), 0)::bigint as duration_seconds
    from recent_training
  ),
  match_summary as (
    select
      count(*)::integer as completed_count,
      count(*) filter (where result = 'win')::integer as wins,
      count(*) filter (where result = 'loss')::integer as losses,
      coalesce(sum(duration_seconds), 0)::bigint as duration_seconds
    from recent_matches
  ),
  plan_summary as (
    select
      count(*) filter (where status = 'planned')::integer as planned_count,
      count(*) filter (where status = 'missed')::integer as missed_count
    from public.training_plans tp, range_start r
    where tp.player_id = (select id from me)
      and tp.scheduled_for >= r.at
  )
  select jsonb_build_object(
    'profile', coalesce((select to_jsonb(me) from me), '{}'::jsonb),
    'disciplines', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', pd.id,
          'sport', pd.sport,
          'discipline', pd.discipline,
          'is_primary', pd.is_primary
        ) order by pd.is_primary desc, pd.sport, pd.discipline
      )
      from public.player_disciplines pd
      where pd.player_id = (select id from me)
    ), '[]'::jsonb),
    'summary', (
      select jsonb_build_object(
        'period_days', 30,
        'time_in_game_seconds', ts.duration_seconds + ms.duration_seconds,
        'trainings_completed', ts.completed_count,
        'trainings_planned', ps.planned_count,
        'trainings_missed', ps.missed_count,
        'matches_completed', ms.completed_count,
        'wins', ms.wins,
        'losses', ms.losses,
        'win_rate', case
          when ms.wins + ms.losses = 0 then 0
          else round(ms.wins::numeric * 100 / (ms.wins + ms.losses), 1)
        end,
        'analytics_unlocked', public.has_feature_access((select id from me), 'profile_analytics'),
        'training_planner_unlocked', public.has_feature_access((select id from me), 'training_planner')
      )
      from training_summary ts
      cross join match_summary ms
      cross join plan_summary ps
    ),
    'upcoming_trainings', coalesce((
      select jsonb_agg(to_jsonb(upcoming) order by upcoming.scheduled_for)
      from (
        select id, title, sport, discipline, scheduled_for,
               target_duration_minutes, venue, status
        from public.training_plans
        where player_id = (select id from me)
          and status = 'planned'
          and scheduled_for >= now()
        order by scheduled_for
        limit 10
      ) upcoming
    ), '[]'::jsonb),
    'recent_trainings', coalesce((
      select jsonb_agg(to_jsonb(history) order by history.occurred_at desc)
      from (
        select
          id,
          sport,
          discipline,
          player_names,
          case
            when final_score is not null and final_score <> '{}'::jsonb then final_score
            else jsonb_build_object(
              'mode','frame',
              'players',jsonb_build_array(
                jsonb_build_object('name',coalesce(player_names[1],'Hráč 1'),'score',coalesce(live_scores[1],0)),
                jsonb_build_object('name',coalesce(player_names[2],'Hráč 2'),'score',coalesce(live_scores[2],0))
              )
            )
          end as final_score,
          coalesce(
            winner_name,
            case
              when coalesce(live_scores[1],0) > coalesce(live_scores[2],0) then player_names[1]
              when coalesce(live_scores[2],0) > coalesce(live_scores[1],0) then player_names[2]
              else null
            end
          ) as winner_name,
          effective_duration_seconds as duration_seconds,
          occurred_at,
          'completed'::text as status,
          status as source_status
        from recent_training
        order by occurred_at desc
        limit 20
      ) history
    ), '[]'::jsonb),
    'recent_matches', coalesce((
      select jsonb_agg(to_jsonb(history) order by history.occurred_at desc)
      from (
        select id, tournament_id, tournament_name, sport, discipline,
               opponent_name, my_score, opponent_score, result,
               duration_seconds, occurred_at
        from recent_matches
        order by occurred_at desc
        limit 20
      ) history
    ), '[]'::jsonb)
  );
$function$;

