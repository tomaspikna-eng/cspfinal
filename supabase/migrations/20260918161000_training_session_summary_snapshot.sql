-- Stable summary snapshot for completed training sessions.
alter table public.training_sessions
  add column if not exists session_summary jsonb not null default '{}'::jsonb;

comment on column public.training_sessions.session_summary is
  'Stable derived metrics for profile cards/details. Refreshed after a completed training session.';

create or replace function public.refresh_my_training_session_summary(p_session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid := auth.uid();
  v_ts public.training_sessions;
  v_players jsonb;
  v_frame_count integer := 0;
  v_duration integer := 0;
  v_avg numeric := null;
  v_fastest integer := null;
  v_longest integer := null;
  v_positive_events integer := 0;
  v_break_and_runs integer := 0;
  v_golden_breaks integer := 0;
  v_combo_wins integer := 0;
  v_three_foul_wins integer := 0;
  v_achievement_count integer := 0;
  v_challenge_count integer := 0;
  v_start timestamptz;
  v_end timestamptz;
  v_summary jsonb;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode='28000';
  end if;

  select * into v_ts
  from public.training_sessions
  where id=p_session_id and owner_id=v_uid;

  if v_ts.id is null then
    raise exception 'training session not found' using errcode='P0002';
  end if;

  v_duration := coalesce(v_ts.duration_seconds,v_ts.elapsed_seconds,0);
  v_end := coalesce(v_ts.completed_at,v_ts.archived_at,v_ts.played_at,v_ts.updated_at,v_ts.created_at);
  v_start := coalesce(
    v_ts.started_at,
    case when v_end is not null and v_duration>0 then v_end-make_interval(secs=>v_duration::double precision) end,
    v_ts.played_at,
    v_ts.created_at
  );

  v_players := case when jsonb_typeof(v_ts.final_score->'players')='array'
    then v_ts.final_score->'players' else '[]'::jsonb end;

  if v_ts.final_score->>'mode'='frame' then
    select coalesce(sum(coalesce((x->>'score')::integer,0)),0)::integer
      into v_frame_count
    from jsonb_array_elements(v_players) x;
  elsif v_ts.final_score->>'mode'='points' then
    select coalesce(sum(coalesce((x->>'frames')::integer,0)),0)::integer
      into v_frame_count
    from jsonb_array_elements(v_players) x;
  elsif v_ts.final_score->>'mode'='darts' then
    select coalesce(sum(coalesce((x->>'legs')::integer,0)),0)::integer
      into v_frame_count
    from jsonb_array_elements(v_players) x;
  else
    select coalesce(sum(coalesce((x->>'sets')::integer,0)),0)::integer
      into v_frame_count
    from jsonb_array_elements(v_players) x;
  end if;

  if v_frame_count=0 and v_ts.live_scores is not null then
    select coalesce(sum(x),0)::integer into v_frame_count from unnest(v_ts.live_scores) x;
  end if;

  if v_frame_count>0 and v_duration>0 then
    v_avg := round(v_duration::numeric/v_frame_count,1);
  end if;

  select
    count(*) filter(where se.score_delta>0 and se.undone_at is null)::integer,
    count(*) filter(where se.event_key='break_and_run' and se.undone_at is null)::integer,
    count(*) filter(where se.event_key='golden_break' and se.undone_at is null)::integer,
    count(*) filter(where se.event_key='combo_win' and se.undone_at is null)::integer,
    count(*) filter(where se.event_key='three_foul_win' and se.undone_at is null)::integer
  into v_positive_events,v_break_and_runs,v_golden_breaks,v_combo_wins,v_three_foul_wins
  from public.score_events se
  where se.training_session_id=v_ts.id;

  -- Per-frame durations are only trusted when event count exactly matches final units.
  if v_ts.final_score->>'mode'='frame' and v_frame_count>0 and v_positive_events=v_frame_count then
    with wins as (
      select se.created_at,
             lag(se.created_at,1,v_start) over(order by se.created_at) as prev_at
      from public.score_events se
      where se.training_session_id=v_ts.id
        and se.score_delta>0
        and se.undone_at is null
    )
    select
      min(greatest(extract(epoch from(created_at-prev_at))::integer,0)),
      max(greatest(extract(epoch from(created_at-prev_at))::integer,0))
    into v_fastest,v_longest
    from wins;
  end if;

  select count(*)::integer into v_achievement_count
  from public.player_achievements pa
  where pa.user_id=v_uid and pa.unlocked_at between v_start and v_end;

  select count(*)::integer into v_challenge_count
  from public.player_challenges pc
  where pc.user_id=v_uid and pc.completed_at between v_start and v_end;

  v_summary := jsonb_build_object(
    'version',1,
    'unit_count',v_frame_count,
    'duration_seconds',v_duration,
    'average_unit_seconds',v_avg,
    'fastest_unit_seconds',v_fastest,
    'longest_unit_seconds',v_longest,
    'break_and_runs',v_break_and_runs,
    'golden_breaks',v_golden_breaks,
    'combo_wins',v_combo_wins,
    'three_foul_wins',v_three_foul_wins,
    'achievement_count',v_achievement_count,
    'challenge_count',v_challenge_count,
    'set_number',coalesce((v_ts.final_score->>'set_number')::integer,1),
    'mode',coalesce(v_ts.final_score->>'mode','frame'),
    'updated_at',now()
  );

  update public.training_sessions
  set session_summary=v_summary
  where id=v_ts.id;

  return v_summary;
end;
$$;

revoke all on function public.refresh_my_training_session_summary(uuid) from public,anon;
grant execute on function public.refresh_my_training_session_summary(uuid) to authenticated,service_role;

-- Include the snapshot in the authenticated player dashboard history payload.
do $$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='get_my_player_profile_dashboard' limit 1;

  if position('session_summary' in v_def)=0 then
    v_def:=replace(v_def,
      'id, sport, discipline, player_names,',
      'id, sport, discipline, player_names, session_summary,');
    execute v_def;
  end if;
end $$;
