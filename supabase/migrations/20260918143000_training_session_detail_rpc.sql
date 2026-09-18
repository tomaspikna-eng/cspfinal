-- Rich drill-down for one authenticated player's training session.
create or replace function public.get_my_training_session_detail(p_session_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_ts public.training_sessions;
  v_end timestamptz;
  v_start timestamptz;
  v_duration bigint;
  v_frame_count integer := 0;
  v_avg_frame numeric;
  v_participants jsonb;
  v_achievements jsonb;
  v_challenges jsonb;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode='28000';
  end if;

  select ts.*
  into v_ts
  from public.training_sessions ts
  where ts.id=p_session_id
    and (
      ts.owner_id=v_uid
      or exists (
        select 1
        from public.training_session_participants tsp
        where tsp.training_session_id=ts.id and tsp.player_id=v_uid
      )
    );

  if v_ts.id is null then
    raise exception 'training session not found' using errcode='P0002';
  end if;

  v_end := coalesce(v_ts.completed_at,v_ts.archived_at,v_ts.played_at,v_ts.updated_at,v_ts.created_at);
  v_duration := coalesce(
    nullif(v_ts.duration_seconds,0),
    nullif(v_ts.elapsed_seconds,0),
    case when v_ts.started_at is not null and v_end is not null
      then greatest(extract(epoch from (v_end-v_ts.started_at))::bigint,0)
      else 0 end
  );
  v_start := coalesce(
    v_ts.started_at,
    case when v_end is not null and v_duration > 0
      then v_end - make_interval(secs => v_duration::double precision)
      else v_ts.played_at end,
    v_ts.created_at
  );

  -- For frame/leg based scoreboard sessions, total scored frames is the most
  -- reliable cross-version count. Fall back to live_scores when old final_score
  -- payloads do not expose player scores.
  if jsonb_typeof(v_ts.final_score->'players')='array' then
    select coalesce(sum(coalesce((x->>'score')::integer,0)),0)::integer
    into v_frame_count
    from jsonb_array_elements(v_ts.final_score->'players') x;
  end if;

  if coalesce(v_frame_count,0)=0 and v_ts.live_scores is not null then
    select coalesce(sum(x),0)::integer into v_frame_count
    from unnest(v_ts.live_scores) x;
  end if;

  if v_frame_count > 0 and v_duration > 0 then
    v_avg_frame := round(v_duration::numeric / v_frame_count,1);
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'slot',q.player_slot,
      'player_id',q.player_id,
      'name',q.display_name,
      'is_me',(q.player_id=v_uid)
    ) order by q.player_slot
  ),'[]'::jsonb)
  into v_participants
  from (
    select tsp.player_slot,tsp.player_id,
           coalesce(nullif(tsp.display_name,''),p.full_name,'Hráč '||tsp.player_slot::text) as display_name
    from public.training_session_participants tsp
    left join public.profiles p on p.id=tsp.player_id
    where tsp.training_session_id=v_ts.id
    union all
    select s.idx::smallint,null::uuid,coalesce(v_ts.player_names[s.idx],'Hráč '||s.idx::text)
    from generate_subscripts(v_ts.player_names,1) s(idx)
    where not exists (
      select 1 from public.training_session_participants tsp
      where tsp.training_session_id=v_ts.id and tsp.player_slot=s.idx
    )
  ) q;

  select coalesce(jsonb_agg(jsonb_build_object(
    'code',pa.achievement_code,
    'name',ad.name,
    'description',ad.description,
    'category',ad.category,
    'points',ad.points,
    'rarity',ad.rarity,
    'unlocked_at',pa.unlocked_at
  ) order by pa.unlocked_at),'[]'::jsonb)
  into v_achievements
  from public.player_achievements pa
  join public.achievement_definitions ad on ad.code=pa.achievement_code
  where pa.user_id=v_uid
    and pa.unlocked_at between v_start and v_end;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,
    'code',c.code,
    'title',c.title,
    'description',c.description,
    'rarity',c.rarity,
    'medal',c.medal,
    'badge_symbol',c.badge_symbol,
    'target_value',c.target_value,
    'unit_label',c.unit_label,
    'completed_at',pc.completed_at
  ) order by pc.completed_at),'[]'::jsonb)
  into v_challenges
  from public.player_challenges pc
  join public.challenges c on c.id=pc.challenge_id
  where pc.user_id=v_uid
    and pc.completed_at is not null
    and pc.completed_at between v_start and v_end;

  return jsonb_build_object(
    'id',v_ts.id,
    'sport',v_ts.sport,
    'discipline',v_ts.discipline,
    'status',v_ts.status,
    'started_at',v_start,
    'ended_at',v_end,
    'played_at',v_ts.played_at,
    'duration_seconds',v_duration,
    'frame_count',v_frame_count,
    'average_frame_seconds',v_avg_frame,
    'race_to',v_ts.race_to,
    'winner_name',v_ts.winner_name,
    'final_score',v_ts.final_score,
    'live_scores',v_ts.live_scores,
    'participants',v_participants,
    'achievements',v_achievements,
    'challenges',v_challenges
  );
end;
$$;

revoke all on function public.get_my_training_session_detail(uuid) from public, anon;
grant execute on function public.get_my_training_session_detail(uuid) to authenticated, service_role;
