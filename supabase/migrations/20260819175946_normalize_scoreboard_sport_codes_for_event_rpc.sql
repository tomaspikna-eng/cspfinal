create or replace function public.normalize_scoreboard_sport_code(p_sport text)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  select case lower(btrim(coalesce(p_sport,'')))
    when 'biliard' then 'billiard'
    when 'billiard' then 'billiard'
    when 'šípky' then 'darts'
    when 'sipky' then 'darts'
    when 'darts' then 'darts'
    when 'other' then 'other'
    when 'ostatné športy' then 'other'
    when 'ostatne sporty' then 'other'
    when 'tabletennis' then 'other'
    when 'table tennis' then 'other'
    when 'stolný tenis' then 'other'
    when 'stolny tenis' then 'other'
    when 'tennis' then 'other'
    when 'tenis' then 'other'
    when 'padel' then 'other'
    when 'bowling' then 'other'
    when 'minigolf' then 'other'
    when 'cards' then 'other'
    when 'karty' then 'other'
    else lower(btrim(coalesce(p_sport,'')))
  end;
$$;

create or replace function public.record_scoreboard_match_event(
  p_match_id uuid,
  p_match_token uuid,
  p_player_slot smallint,
  p_event_key text,
  p_value numeric default null,
  p_source text default 'manual',
  p_source_device_ref text default null,
  p_idempotency_key text default null,
  p_confidence numeric default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_match public.matches%rowtype;
  v_sport text;
  v_discipline text;
  v_action public.score_action_definitions%rowtype;
  v_tournament_player_id uuid;
  v_player_profile_id uuid;
  v_score1 integer;
  v_score2 integer;
  v_metric_value numeric;
  v_event public.score_events%rowtype;
begin
  if p_match_id is null or p_match_token is null then raise exception 'MATCH_AND_TOKEN_REQUIRED'; end if;
  if p_player_slot not in (1,2) then raise exception 'INVALID_PLAYER_SLOT'; end if;
  if p_source not in ('manual','referee','ai','device','import') then raise exception 'INVALID_EVENT_SOURCE'; end if;
  if p_confidence is not null and (p_confidence < 0 or p_confidence > 1) then raise exception 'INVALID_CONFIDENCE'; end if;
  if p_metadata is null or jsonb_typeof(p_metadata) <> 'object' then raise exception 'METADATA_MUST_BE_OBJECT'; end if;

  select m.* into v_match
  from public.matches m
  where m.id = p_match_id and m.public_token = p_match_token
  for update;

  if v_match.id is null then raise exception 'MATCH_NOT_FOUND_OR_INVALID_TOKEN'; end if;
  if v_match.status not in ('live','in_progress') then raise exception 'MATCH_NOT_RUNNING'; end if;

  select public.normalize_scoreboard_sport_code(t.sport), lower(btrim(t.discipline))
    into v_sport, v_discipline
  from public.tournaments t
  where t.id = v_match.tournament_id;

  select d.* into v_action
  from public.score_action_definitions d
  where d.is_active
    and d.sport_code = v_sport
    and d.discipline_code in (v_discipline, '*')
    and d.event_key = lower(btrim(p_event_key))
    and 'tournament' = any(d.available_in)
  order by (d.discipline_code = v_discipline) desc
  limit 1;

  if v_action.id is null then raise exception 'ACTION_NOT_AVAILABLE_FOR_DISCIPLINE'; end if;

  if v_action.metric_value_mode = 'input' then
    if p_value is null then raise exception 'ACTION_VALUE_REQUIRED'; end if;
    if v_action.value_min is not null and p_value < v_action.value_min then raise exception 'ACTION_VALUE_TOO_LOW'; end if;
    if v_action.value_max is not null and p_value > v_action.value_max then raise exception 'ACTION_VALUE_TOO_HIGH'; end if;
    v_metric_value := p_value;
  else
    v_metric_value := v_action.metric_value_default;
  end if;

  if p_idempotency_key is not null then
    select e.* into v_event
    from public.score_events e
    where e.match_id = p_match_id and e.idempotency_key = p_idempotency_key;
    if v_event.id is not null then
      return jsonb_build_object('event_id',v_event.id,'score1',coalesce(v_match.score1,0),'score2',coalesce(v_match.score2,0),'duplicate',true,'undone',v_event.undone_at is not null);
    end if;
  end if;

  v_tournament_player_id := case when p_player_slot=1 then v_match.player1_id else v_match.player2_id end;
  if v_tournament_player_id is null then raise exception 'PLAYER_SLOT_IS_EMPTY'; end if;

  select tp.user_id into v_player_profile_id from public.tournament_players tp where tp.id = v_tournament_player_id;

  v_score1 := coalesce(v_match.score1,0) + case when p_player_slot=1 then v_action.score_delta else 0 end;
  v_score2 := coalesce(v_match.score2,0) + case when p_player_slot=2 then v_action.score_delta else 0 end;
  if v_score1 < 0 or v_score2 < 0 then raise exception 'SCORE_CANNOT_BE_NEGATIVE'; end if;

  update public.matches set score1=v_score1, score2=v_score2, updated_at=now() where id=p_match_id;
  update public.tournament_resource_assignments set score1=v_score1, score2=v_score2 where match_id=p_match_id and released_at is null;

  insert into public.score_events (
    action_definition_id,match_id,tournament_player_id,player_profile_id,player_slot,
    sport,discipline,event_key,metric_key,score_delta,metric_value,
    source,source_device_ref,idempotency_key,confidence,metadata,created_by
  ) values (
    v_action.id,p_match_id,v_tournament_player_id,v_player_profile_id,p_player_slot,
    v_sport,v_discipline,v_action.event_key,v_action.metric_key,v_action.score_delta,
    case when v_action.metric_key is null then null else v_metric_value end,
    p_source,nullif(btrim(p_source_device_ref),''),nullif(btrim(p_idempotency_key),''),
    p_confidence,p_metadata,auth.uid()
  ) returning * into v_event;

  return jsonb_build_object('event_id',v_event.id,'event_key',v_event.event_key,'score_delta',v_event.score_delta,'metric_key',v_event.metric_key,'metric_value',v_event.metric_value,'score1',v_score1,'score2',v_score2,'duplicate',false,'undone',false);
end;
$$;

create or replace function public.record_training_score_event(
  p_training_session_id uuid,
  p_player_slot smallint,
  p_event_key text,
  p_value numeric default null,
  p_source text default 'manual',
  p_source_device_ref text default null,
  p_idempotency_key text default null,
  p_confidence numeric default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_session public.training_sessions%rowtype;
  v_action public.score_action_definitions%rowtype;
  v_participant public.training_session_participants%rowtype;
  v_scores integer[];
  v_metric_value numeric;
  v_event public.score_events%rowtype;
  v_sport text;
  v_discipline text;
begin
  if auth.uid() is null then raise exception 'AUTHENTICATION_REQUIRED'; end if;
  if p_player_slot not between 1 and 3 then raise exception 'INVALID_PLAYER_SLOT'; end if;
  if p_source not in ('manual','referee','ai','device','import') then raise exception 'INVALID_EVENT_SOURCE'; end if;
  if p_confidence is not null and (p_confidence < 0 or p_confidence > 1) then raise exception 'INVALID_CONFIDENCE'; end if;
  if p_metadata is null or jsonb_typeof(p_metadata) <> 'object' then raise exception 'METADATA_MUST_BE_OBJECT'; end if;

  select ts.* into v_session
  from public.training_sessions ts
  where ts.id=p_training_session_id and ts.owner_id=auth.uid()
  for update;

  if v_session.id is null then raise exception 'TRAINING_SESSION_NOT_FOUND_OR_ACCESS_DENIED'; end if;
  if v_session.status not in ('active','paused') then raise exception 'TRAINING_SESSION_NOT_RUNNING'; end if;

  v_sport := public.normalize_scoreboard_sport_code(v_session.sport);
  v_discipline := lower(btrim(v_session.discipline));

  select d.* into v_action
  from public.score_action_definitions d
  where d.is_active
    and d.sport_code=v_sport
    and d.discipline_code in (v_discipline,'*')
    and d.event_key=lower(btrim(p_event_key))
    and 'training'=any(d.available_in)
  order by (d.discipline_code=v_discipline) desc
  limit 1;

  if v_action.id is null then raise exception 'ACTION_NOT_AVAILABLE_FOR_DISCIPLINE'; end if;

  if v_action.metric_value_mode='input' then
    if p_value is null then raise exception 'ACTION_VALUE_REQUIRED'; end if;
    if v_action.value_min is not null and p_value<v_action.value_min then raise exception 'ACTION_VALUE_TOO_LOW'; end if;
    if v_action.value_max is not null and p_value>v_action.value_max then raise exception 'ACTION_VALUE_TOO_HIGH'; end if;
    v_metric_value:=p_value;
  else
    v_metric_value:=v_action.metric_value_default;
  end if;

  if p_idempotency_key is not null then
    select e.* into v_event
    from public.score_events e
    where e.training_session_id=p_training_session_id and e.idempotency_key=p_idempotency_key;
    if v_event.id is not null then
      return jsonb_build_object('event_id',v_event.id,'live_scores',v_session.live_scores,'duplicate',true,'undone',v_event.undone_at is not null);
    end if;
  end if;

  select tsp.* into v_participant
  from public.training_session_participants tsp
  where tsp.training_session_id=p_training_session_id and tsp.player_slot=p_player_slot;

  if v_participant.id is null and p_player_slot=1 then
    insert into public.training_session_participants(training_session_id,player_slot,player_id,display_name)
    values (p_training_session_id,1,auth.uid(),coalesce(nullif(v_session.player_names[1],''),'Hráč 1'))
    on conflict (training_session_id,player_slot) do nothing;
    select tsp.* into v_participant from public.training_session_participants tsp where tsp.training_session_id=p_training_session_id and tsp.player_slot=1;
  end if;

  if v_participant.id is null then raise exception 'TRAINING_PARTICIPANT_NOT_CONFIGURED'; end if;

  v_scores:=coalesce(v_session.live_scores,array[0,0,0]::integer[]);
  v_scores[p_player_slot]:=coalesce(v_scores[p_player_slot],0)+v_action.score_delta;
  if v_scores[p_player_slot]<0 then raise exception 'SCORE_CANNOT_BE_NEGATIVE'; end if;

  update public.training_sessions set live_scores=v_scores,updated_at=now() where id=p_training_session_id;

  insert into public.score_events (
    action_definition_id,training_session_id,training_participant_id,player_profile_id,player_slot,
    sport,discipline,event_key,metric_key,score_delta,metric_value,
    source,source_device_ref,idempotency_key,confidence,metadata,created_by
  ) values (
    v_action.id,p_training_session_id,v_participant.id,v_participant.player_id,p_player_slot,
    v_sport,v_discipline,v_action.event_key,v_action.metric_key,v_action.score_delta,
    case when v_action.metric_key is null then null else v_metric_value end,
    p_source,nullif(btrim(p_source_device_ref),''),nullif(btrim(p_idempotency_key),''),
    p_confidence,p_metadata,auth.uid()
  ) returning * into v_event;

  return jsonb_build_object('event_id',v_event.id,'event_key',v_event.event_key,'score_delta',v_event.score_delta,'metric_key',v_event.metric_key,'metric_value',v_event.metric_value,'live_scores',v_scores,'duplicate',false,'undone',false);
end;
$$;

