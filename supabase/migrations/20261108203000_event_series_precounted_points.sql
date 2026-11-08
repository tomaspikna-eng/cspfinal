-- Allow historical round results to be displayed without double-counting
-- points that were already included in the imported series total.

update public.tournament_results
set metadata = coalesce(metadata,'{}'::jsonb) || '{"series_points_precounted":true}'::jsonb,
    updated_at = now()
where tournament_id = '4d6f89ad-9e22-4495-9543-c983d1185f09'::uuid;

create or replace view public.event_series_standings
with (security_invoker=true)
as
with aggregated as (
  select
    r.series_id,
    r.series_title,
    r.total_rounds,
    r.best_results_count,
    coalesce(s.ranking_config -> 'tie_breakers','[]'::jsonb) as tie_breakers,
    r.player_identity_id,
    (array_agg(r.profile_id order by r.series_round_number desc) filter (where r.profile_id is not null))[1] as profile_id,
    (array_agg(r.player_name order by r.series_round_number desc))[1] as player_name,
    count(*)::integer as rounds_played,
    count(*) filter (where r.is_counted)::integer as counted_rounds,
    coalesce(
      sum(
        case
          when coalesce((tr.metadata->>'series_points_precounted')::boolean,false) then 0
          else r.points
        end
      ) filter (where r.is_counted),
      0
    )::integer as total_points,
    count(*) filter (where r.is_counted and r.final_position=1)::integer as victories,
    count(*) filter (where r.is_counted and r.final_position=2)::integer as runner_up_finishes,
    count(*) filter (where r.is_counted and r.final_position=3)::integer as third_places,
    min(r.final_position) filter (where r.is_counted) as best_position,
    coalesce(sum(r.wins) filter (where r.is_counted),0)::integer as match_wins,
    max(r.series_round_number) as latest_round_number,
    (array_agg(r.points order by r.series_round_number desc))[1] as latest_round_points
  from public.event_series_round_results r
  join public.event_series s on s.id=r.series_id
  left join public.tournament_results tr on tr.id=r.tournament_result_id
  group by
    r.series_id,r.series_title,r.total_rounds,r.best_results_count,
    s.ranking_config,r.player_identity_id
),
ranked as (
  select
    a.*,
    rank() over (
      partition by a.series_id
      order by
        a.total_points desc,
        (case when a.tie_breakers ? 'victories' then a.victories else null end) desc nulls last,
        (case when a.tie_breakers ? 'runner_up_finishes' then a.runner_up_finishes else null end) desc nulls last,
        (case when a.tie_breakers ? 'third_places' then a.third_places else null end) desc nulls last,
        (case when a.tie_breakers ? 'best_position' then a.best_position else null end),
        (case when a.tie_breakers ? 'match_wins' then a.match_wins else null end) desc nulls last
    )::integer as standing_position
  from aggregated a
)
select
  standing_position,
  series_id,
  series_title,
  total_rounds,
  best_results_count,
  player_identity_id,
  profile_id,
  player_name,
  total_points,
  rounds_played,
  counted_rounds,
  victories,
  runner_up_finishes,
  third_places,
  best_position,
  match_wins,
  latest_round_number,
  latest_round_points
from ranked;
