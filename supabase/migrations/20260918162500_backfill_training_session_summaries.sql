-- Backfill summary snapshots for existing completed training sessions.
with base as (
  select
    ts.id,
    ts.owner_id,
    coalesce(ts.duration_seconds,ts.elapsed_seconds,0)::integer as duration_seconds,
    coalesce(ts.completed_at,ts.archived_at,ts.played_at,ts.updated_at,ts.created_at) as ended_at,
    coalesce(
      ts.started_at,
      case when coalesce(ts.duration_seconds,ts.elapsed_seconds,0)>0
        then coalesce(ts.completed_at,ts.archived_at,ts.played_at,ts.updated_at,ts.created_at)
             - make_interval(secs=>coalesce(ts.duration_seconds,ts.elapsed_seconds,0)::double precision)
      end,
      ts.played_at,
      ts.created_at
    ) as started_at,
    coalesce(ts.final_score->>'mode','frame') as mode,
    coalesce((ts.final_score->>'set_number')::integer,1) as set_number,
    case
      when jsonb_typeof(ts.final_score->'players')='array' and ts.final_score->>'mode'='frame' then
        (select coalesce(sum(coalesce((x->>'score')::integer,0)),0)::integer from jsonb_array_elements(ts.final_score->'players') x)
      when jsonb_typeof(ts.final_score->'players')='array' and ts.final_score->>'mode'='points' then
        (select coalesce(sum(coalesce((x->>'frames')::integer,0)),0)::integer from jsonb_array_elements(ts.final_score->'players') x)
      when jsonb_typeof(ts.final_score->'players')='array' and ts.final_score->>'mode'='darts' then
        (select coalesce(sum(coalesce((x->>'legs')::integer,0)),0)::integer from jsonb_array_elements(ts.final_score->'players') x)
      when jsonb_typeof(ts.final_score->'players')='array' then
        (select coalesce(sum(coalesce((x->>'sets')::integer,0)),0)::integer from jsonb_array_elements(ts.final_score->'players') x)
      else coalesce((select sum(v)::integer from unnest(ts.live_scores) v),0)
    end as unit_count
  from public.training_sessions ts
  where ts.status='completed'
),
event_agg as (
  select
    se.training_session_id,
    count(*) filter(where se.score_delta>0 and se.undone_at is null)::integer as positive_events,
    count(*) filter(where se.event_key='break_and_run' and se.undone_at is null)::integer as break_and_runs,
    count(*) filter(where se.event_key='golden_break' and se.undone_at is null)::integer as golden_breaks,
    count(*) filter(where se.event_key='combo_win' and se.undone_at is null)::integer as combo_wins,
    count(*) filter(where se.event_key='three_foul_win' and se.undone_at is null)::integer as three_foul_wins
  from public.score_events se
  group by se.training_session_id
),
positive_timeline as (
  select
    se.training_session_id,
    greatest(
      extract(epoch from (
        se.created_at
        - lag(se.created_at,1,b.started_at) over(partition by se.training_session_id order by se.created_at)
      ))::integer,
      0
    ) as frame_seconds
  from public.score_events se
  join base b on b.id=se.training_session_id
  where se.score_delta>0 and se.undone_at is null
),
event_duration as (
  select training_session_id,min(frame_seconds)::integer as fastest,max(frame_seconds)::integer as longest
  from positive_timeline
  group by training_session_id
)
update public.training_sessions ts
set session_summary=jsonb_build_object(
  'version',1,
  'unit_count',b.unit_count,
  'duration_seconds',b.duration_seconds,
  'average_unit_seconds',case when b.unit_count>0 and b.duration_seconds>0 then round(b.duration_seconds::numeric/b.unit_count,1) else null end,
  'fastest_unit_seconds',case when b.mode='frame' and coalesce(ea.positive_events,0)=b.unit_count then ed.fastest else null end,
  'longest_unit_seconds',case when b.mode='frame' and coalesce(ea.positive_events,0)=b.unit_count then ed.longest else null end,
  'break_and_runs',coalesce(ea.break_and_runs,0),
  'golden_breaks',coalesce(ea.golden_breaks,0),
  'combo_wins',coalesce(ea.combo_wins,0),
  'three_foul_wins',coalesce(ea.three_foul_wins,0),
  'achievement_count',(
    select count(*)::integer
    from public.player_achievements pa
    where pa.user_id=b.owner_id and pa.unlocked_at between b.started_at and b.ended_at
  ),
  'challenge_count',(
    select count(*)::integer
    from public.player_challenges pc
    where pc.user_id=b.owner_id and pc.completed_at between b.started_at and b.ended_at
  ),
  'set_number',b.set_number,
  'mode',b.mode,
  'updated_at',now()
)
from base b
left join event_agg ea on ea.training_session_id=b.id
left join event_duration ed on ed.training_session_id=b.id
where ts.id=b.id;