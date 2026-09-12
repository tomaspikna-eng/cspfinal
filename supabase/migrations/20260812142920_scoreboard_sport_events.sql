
create table public.score_action_definitions (
  id uuid primary key default gen_random_uuid(),
  sport_code text not null,
  discipline_code text not null,
  event_key text not null,
  label text not null,
  label_key text not null,
  score_delta integer not null default 0,
  metric_key text,
  metric_value_mode text not null default 'fixed'
    check (metric_value_mode in ('fixed','input')),
  metric_value_default numeric not null default 1,
  value_min numeric,
  value_max numeric,
  available_in text[] not null default array['tournament','training']::text[],
  button_style text not null default 'secondary'
    check (button_style in ('primary','secondary','positive','warning','danger')),
  sort_order smallint not null default 100,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint score_action_definition_codes_check check (
    sport_code = lower(btrim(sport_code))
    and discipline_code = lower(btrim(discipline_code))
    and event_key = lower(btrim(event_key))
    and length(sport_code) between 1 and 80
    and length(discipline_code) between 1 and 120
    and length(event_key) between 1 and 100
  ),
  constraint score_action_definition_value_range_check check (
    value_min is null or value_max is null or value_min <= value_max
  ),
  constraint score_action_definition_context_check check (
    cardinality(available_in) > 0
    and available_in <@ array['tournament','training']::text[]
  ),
  unique (sport_code, discipline_code, event_key)
);

comment on table public.score_action_definitions is
  'Data-driven CTA catalogue for scoreboards. Exact discipline rows override wildcard rows; frontends must not hard-code sport metrics.';
comment on column public.score_action_definitions.score_delta is
  'Change to the main match unit (rack/frame/leg/point) applied to the player whose CTA is pressed.';
comment on column public.score_action_definitions.metric_value_mode is
  'fixed uses metric_value_default; input uses the numeric value sent by the scoreboard, e.g. checkout or snooker break.';

alter table public.score_action_definitions enable row level security;

create policy score_action_definitions_read
on public.score_action_definitions
for select
to anon, authenticated
using (is_active);

grant select on public.score_action_definitions to anon, authenticated;

create table public.training_session_participants (
  id uuid primary key default gen_random_uuid(),
  training_session_id uuid not null references public.training_sessions(id) on delete cascade,
  player_slot smallint not null check (player_slot between 1 and 3),
  player_id uuid references public.profiles(id) on delete set null,
  display_name text not null check (length(btrim(display_name)) between 1 and 160),
  created_at timestamptz not null default now(),
  unique (training_session_id, player_slot),
  unique nulls not distinct (training_session_id, player_id)
);

comment on table public.training_session_participants is
  'Participants linked to future training scoreboard events. Guests keep a display name while linked CSP accounts also receive profile metrics.';

alter table public.training_session_participants enable row level security;

create policy training_session_participants_read
on public.training_session_participants
for select
to authenticated
using (
  player_id = (select auth.uid())
  or exists (
    select 1
    from public.training_sessions ts
    where ts.id = training_session_id
      and ts.owner_id = (select auth.uid())
  )
);

create policy training_session_participants_insert_owner
on public.training_session_participants
for insert
to authenticated
with check (
  exists (
    select 1
    from public.training_sessions ts
    where ts.id = training_session_id
      and ts.owner_id = (select auth.uid())
  )
);

create policy training_session_participants_update_owner
on public.training_session_participants
for update
to authenticated
using (
  exists (
    select 1
    from public.training_sessions ts
    where ts.id = training_session_id
      and ts.owner_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1
    from public.training_sessions ts
    where ts.id = training_session_id
      and ts.owner_id = (select auth.uid())
  )
);

create policy training_session_participants_delete_owner
on public.training_session_participants
for delete
to authenticated
using (
  exists (
    select 1
    from public.training_sessions ts
    where ts.id = training_session_id
      and ts.owner_id = (select auth.uid())
  )
);

grant select, insert, update, delete
on public.training_session_participants
to authenticated;

alter table public.training_sessions
  add column live_scores integer[] not null default array[0,0,0]::integer[];

alter table public.training_sessions
  add constraint training_sessions_live_scores_check
  check (
    cardinality(live_scores) = 3
    and live_scores[1] >= 0
    and live_scores[2] >= 0
    and live_scores[3] >= 0
  );

comment on column public.training_sessions.live_scores is
  'Live main score by participant slot. Updated atomically with score events; final_score remains the completed-session snapshot.';

create table public.score_events (
  id uuid primary key default gen_random_uuid(),
  action_definition_id uuid not null references public.score_action_definitions(id) on delete restrict,
  match_id uuid references public.matches(id) on delete cascade,
  training_session_id uuid references public.training_sessions(id) on delete cascade,
  tournament_player_id uuid references public.tournament_players(id) on delete set null,
  training_participant_id uuid references public.training_session_participants(id) on delete set null,
  player_profile_id uuid references public.profiles(id) on delete set null,
  player_slot smallint not null check (player_slot between 1 and 3),
  sport text not null,
  discipline text not null,
  event_key text not null,
  metric_key text,
  score_delta integer not null default 0,
  metric_value numeric,
  source text not null default 'manual'
    check (source in ('manual','referee','ai','device','import')),
  source_device_ref text,
  idempotency_key text,
  confidence numeric,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  undone_at timestamptz,
  undone_by uuid references public.profiles(id) on delete set null,
  undo_reason text,
  constraint score_events_one_context_check check (
    (match_id is not null and training_session_id is null and training_participant_id is null)
    or
    (match_id is null and training_session_id is not null and tournament_player_id is null)
  ),
  constraint score_events_confidence_check check (
    confidence is null or confidence between 0 and 1
  ),
  constraint score_events_idempotency_key_check check (
    idempotency_key is null or length(idempotency_key) between 1 and 200
  ),
  constraint score_events_metadata_object_check check (
    jsonb_typeof(metadata) = 'object'
  )
);

comment on table public.score_events is
  'Immutable sport-event log behind both CSP scoreboards. Undo marks an event and reverses its score effect instead of deleting official history.';
comment on column public.score_events.source is
  'manual/referee are human inputs; ai/device prepare the same API for OMNI or another camera referee.';
comment on column public.score_events.confidence is
  'Optional 0..1 confidence supplied by an AI referee.';

create unique index score_events_match_idempotency_uq
  on public.score_events(match_id, idempotency_key)
  where match_id is not null and idempotency_key is not null;

create unique index score_events_training_idempotency_uq
  on public.score_events(training_session_id, idempotency_key)
  where training_session_id is not null and idempotency_key is not null;

create index score_events_match_created_idx
  on public.score_events(match_id, created_at desc)
  where match_id is not null;

create index score_events_training_created_idx
  on public.score_events(training_session_id, created_at desc)
  where training_session_id is not null;

create index score_events_player_metrics_idx
  on public.score_events(player_profile_id, sport, discipline, metric_key)
  where undone_at is null and metric_key is not null;

alter table public.score_events enable row level security;

create policy score_events_read_related
on public.score_events
for select
to authenticated
using (
  player_profile_id = (select auth.uid())
  or exists (
    select 1
    from public.matches m
    join public.tournaments t on t.id = m.tournament_id
    where m.id = match_id
      and (
        t.owner_id = (select auth.uid())
        or public.is_admin((select auth.uid()))
        or exists (
          select 1
          from public.tournament_players tp
          where tp.id in (m.player1_id, m.player2_id)
            and tp.user_id = (select auth.uid())
        )
      )
  )
  or exists (
    select 1
    from public.training_sessions ts
    where ts.id = training_session_id
      and ts.owner_id = (select auth.uid())
  )
);

grant select on public.score_events to authenticated;

insert into public.score_action_definitions
  (sport_code, discipline_code, event_key, label, label_key, score_delta, metric_key, metric_value_mode, metric_value_default, value_min, value_max, available_in, button_style, sort_order)
values
  ('billiard','8-ball','standard_point','+1','score.action.standard_point',1,null,'fixed',1,null,null,array['tournament','training'],'primary',10),
  ('billiard','8-ball','break_and_run','BREAK & RUN','score.action.break_and_run',1,'break_and_run','fixed',1,null,null,array['tournament','training'],'positive',20),
  ('billiard','8-ball','eight_on_break','8 ON BREAK','score.action.eight_on_break',1,'eight_on_break','fixed',1,null,null,array['tournament','training'],'positive',30),

  ('billiard','9-ball','standard_point','+1','score.action.standard_point',1,null,'fixed',1,null,null,array['tournament','training'],'primary',10),
  ('billiard','9-ball','break_and_run','BREAK & RUN','score.action.break_and_run',1,'break_and_run','fixed',1,null,null,array['tournament','training'],'positive',20),
  ('billiard','9-ball','golden_break','GOLDEN BREAK','score.action.golden_break',1,'golden_break','fixed',1,null,null,array['tournament','training'],'positive',30),
  ('billiard','9-ball','three_foul_win','3 FOULS','score.action.three_foul_win',1,'three_foul_win','fixed',1,null,null,array['tournament','training'],'warning',40),

  ('billiard','10-ball','standard_point','+1','score.action.standard_point',1,null,'fixed',1,null,null,array['tournament','training'],'primary',10),
  ('billiard','10-ball','break_and_run','BREAK & RUN','score.action.break_and_run',1,'break_and_run','fixed',1,null,null,array['tournament','training'],'positive',20),
  ('billiard','10-ball','golden_break','GOLDEN BREAK','score.action.golden_break',1,'golden_break','fixed',1,null,null,array['tournament','training'],'positive',30),
  ('billiard','10-ball','three_foul_win','3 FOULS','score.action.three_foul_win',1,'three_foul_win','fixed',1,null,null,array['tournament','training'],'warning',40),

  ('billiard','snooker','frame_win','+1 FRAME','score.action.frame_win',1,'frame_win','fixed',1,null,null,array['tournament','training'],'primary',10),
  ('billiard','snooker','snooker_break','BREAK','score.action.snooker_break',0,'snooker_break','input',1,1,147,array['tournament','training'],'secondary',20),
  ('billiard','snooker','century_break','CENTURY','score.action.century_break',0,'century_break','input',100,100,147,array['tournament','training'],'positive',30),
  ('billiard','snooker','total_clearance','TOTAL CLEARANCE','score.action.total_clearance',1,'total_clearance','fixed',1,null,null,array['tournament','training'],'positive',40),

  ('darts','501','leg_win','+1 LEG','score.action.leg_win',1,'leg_win','fixed',1,null,null,array['tournament','training'],'primary',10),
  ('darts','501','checkout','CHECKOUT','score.action.checkout',1,'checkout','input',1,2,170,array['tournament','training'],'positive',20),
  ('darts','501','score_180','180','score.action.score_180',0,'score_180','fixed',1,null,null,array['tournament','training'],'positive',30),
  ('darts','501','bust','BUST','score.action.bust',0,'bust','fixed',1,null,null,array['tournament','training'],'warning',40),
  ('darts','501','nine_dart_leg','9 DART LEG','score.action.nine_dart_leg',1,'nine_dart_leg','fixed',1,null,null,array['tournament','training'],'positive',50),

  ('darts','301','leg_win','+1 LEG','score.action.leg_win',1,'leg_win','fixed',1,null,null,array['tournament','training'],'primary',10),
  ('darts','301','checkout','CHECKOUT','score.action.checkout',1,'checkout','input',1,2,170,array['tournament','training'],'positive',20),
  ('darts','301','score_180','180','score.action.score_180',0,'score_180','fixed',1,null,null,array['tournament','training'],'positive',30),
  ('darts','301','bust','BUST','score.action.bust',0,'bust','fixed',1,null,null,array['tournament','training'],'warning',40),

  ('other','*','standard_point','+1','score.action.standard_point',1,null,'fixed',1,null,null,array['tournament','training'],'primary',10),
  ('other','*','ace','ACE','score.action.ace',1,'ace','fixed',1,null,null,array['tournament','training'],'positive',20);

create or replace function public.get_scoreboard_event_actions(
  p_sport text,
  p_discipline text,
  p_context text default 'tournament'
)
returns table (
  event_key text,
  label text,
  label_key text,
  score_delta integer,
  metric_key text,
  value_required boolean,
  value_min numeric,
  value_max numeric,
  button_style text,
  sort_order smallint
)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select distinct on (d.event_key)
    d.event_key,
    d.label,
    d.label_key,
    d.score_delta,
    d.metric_key,
    d.metric_value_mode = 'input',
    d.value_min,
    d.value_max,
    d.button_style,
    d.sort_order
  from public.score_action_definitions d
  where d.is_active
    and d.sport_code = lower(btrim(p_sport))
    and d.discipline_code in (lower(btrim(p_discipline)), '*')
    and p_context = any(d.available_in)
  order by d.event_key,
           (d.discipline_code = lower(btrim(p_discipline))) desc,
           d.sort_order;
$$;

revoke all on function public.get_scoreboard_event_actions(text,text,text) from public;
grant execute on function public.get_scoreboard_event_actions(text,text,text) to anon, authenticated;

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
  if p_match_id is null or p_match_token is null then
    raise exception 'MATCH_AND_TOKEN_REQUIRED';
  end if;
  if p_player_slot not in (1,2) then
    raise exception 'INVALID_PLAYER_SLOT';
  end if;
  if p_source not in ('manual','referee','ai','device','import') then
    raise exception 'INVALID_EVENT_SOURCE';
  end if;
  if p_confidence is not null and (p_confidence < 0 or p_confidence > 1) then
    raise exception 'INVALID_CONFIDENCE';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata) <> 'object' then
    raise exception 'METADATA_MUST_BE_OBJECT';
  end if;

  select m.* into v_match
  from public.matches m
  where m.id = p_match_id
    and m.public_token = p_match_token
  for update;

  if v_match.id is null then
    raise exception 'MATCH_NOT_FOUND_OR_INVALID_TOKEN';
  end if;
  if v_match.status not in ('live','in_progress') then
    raise exception 'MATCH_NOT_RUNNING';
  end if;

  select lower(btrim(t.sport)), lower(btrim(t.discipline))
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

  if v_action.id is null then
    raise exception 'ACTION_NOT_AVAILABLE_FOR_DISCIPLINE';
  end if;

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
    where e.match_id = p_match_id
      and e.idempotency_key = p_idempotency_key;
    if v_event.id is not null then
      return jsonb_build_object(
        'event_id',v_event.id,
        'score1',coalesce(v_match.score1,0),
        'score2',coalesce(v_match.score2,0),
        'duplicate',true,
        'undone',v_event.undone_at is not null
      );
    end if;
  end if;

  v_tournament_player_id := case when p_player_slot=1 then v_match.player1_id else v_match.player2_id end;
  if v_tournament_player_id is null then raise exception 'PLAYER_SLOT_IS_EMPTY'; end if;

  select tp.user_id into v_player_profile_id
  from public.tournament_players tp
  where tp.id = v_tournament_player_id;

  v_score1 := coalesce(v_match.score1,0) + case when p_player_slot=1 then v_action.score_delta else 0 end;
  v_score2 := coalesce(v_match.score2,0) + case when p_player_slot=2 then v_action.score_delta else 0 end;

  if v_score1 < 0 or v_score2 < 0 then raise exception 'SCORE_CANNOT_BE_NEGATIVE'; end if;

  update public.matches
  set score1=v_score1, score2=v_score2, updated_at=now()
  where id=p_match_id;

  update public.tournament_resource_assignments
  set score1=v_score1, score2=v_score2
  where match_id=p_match_id and released_at is null;

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
  )
  returning * into v_event;

  return jsonb_build_object(
    'event_id',v_event.id,
    'event_key',v_event.event_key,
    'score_delta',v_event.score_delta,
    'metric_key',v_event.metric_key,
    'metric_value',v_event.metric_value,
    'score1',v_score1,
    'score2',v_score2,
    'duplicate',false,
    'undone',false
  );
end;
$$;

revoke all on function public.record_scoreboard_match_event(uuid,uuid,smallint,text,numeric,text,text,text,numeric,jsonb) from public;
grant execute on function public.record_scoreboard_match_event(uuid,uuid,smallint,text,numeric,text,text,text,numeric,jsonb) to anon, authenticated;

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
  where ts.id=p_training_session_id
    and ts.owner_id=auth.uid()
  for update;

  if v_session.id is null then raise exception 'TRAINING_SESSION_NOT_FOUND_OR_ACCESS_DENIED'; end if;
  if v_session.status not in ('active','paused') then raise exception 'TRAINING_SESSION_NOT_RUNNING'; end if;

  v_sport := lower(btrim(v_session.sport));
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
    where e.training_session_id=p_training_session_id
      and e.idempotency_key=p_idempotency_key;
    if v_event.id is not null then
      return jsonb_build_object(
        'event_id',v_event.id,
        'live_scores',v_session.live_scores,
        'duplicate',true,
        'undone',v_event.undone_at is not null
      );
    end if;
  end if;

  select tsp.* into v_participant
  from public.training_session_participants tsp
  where tsp.training_session_id=p_training_session_id
    and tsp.player_slot=p_player_slot;

  if v_participant.id is null and p_player_slot=1 then
    insert into public.training_session_participants(training_session_id,player_slot,player_id,display_name)
    values (
      p_training_session_id,1,auth.uid(),
      coalesce(nullif(v_session.player_names[1],''),'Hráč 1')
    )
    on conflict (training_session_id,player_slot) do nothing;

    select tsp.* into v_participant
    from public.training_session_participants tsp
    where tsp.training_session_id=p_training_session_id
      and tsp.player_slot=1;
  end if;

  if v_participant.id is null then raise exception 'TRAINING_PARTICIPANT_NOT_CONFIGURED'; end if;

  v_scores:=coalesce(v_session.live_scores,array[0,0,0]::integer[]);
  v_scores[p_player_slot]:=coalesce(v_scores[p_player_slot],0)+v_action.score_delta;
  if v_scores[p_player_slot]<0 then raise exception 'SCORE_CANNOT_BE_NEGATIVE'; end if;

  update public.training_sessions
  set live_scores=v_scores,updated_at=now()
  where id=p_training_session_id;

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
  )
  returning * into v_event;

  return jsonb_build_object(
    'event_id',v_event.id,
    'event_key',v_event.event_key,
    'score_delta',v_event.score_delta,
    'metric_key',v_event.metric_key,
    'metric_value',v_event.metric_value,
    'live_scores',v_scores,
    'duplicate',false,
    'undone',false
  );
end;
$$;

revoke all on function public.record_training_score_event(uuid,smallint,text,numeric,text,text,text,numeric,jsonb) from public;
grant execute on function public.record_training_score_event(uuid,smallint,text,numeric,text,text,text,numeric,jsonb) to authenticated;

create or replace function public.undo_scoreboard_event(
  p_event_id uuid,
  p_match_token uuid default null,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_event public.score_events%rowtype;
  v_match public.matches%rowtype;
  v_session public.training_sessions%rowtype;
  v_score1 integer;
  v_score2 integer;
  v_scores integer[];
begin
  select e.* into v_event
  from public.score_events e
  where e.id=p_event_id
  for update;

  if v_event.id is null then raise exception 'EVENT_NOT_FOUND'; end if;

  if v_event.undone_at is not null then
    return jsonb_build_object('event_id',v_event.id,'undone',true,'duplicate',true);
  end if;

  if v_event.match_id is not null then
    select m.* into v_match
    from public.matches m
    where m.id=v_event.match_id
      and m.public_token=p_match_token
    for update;

    if v_match.id is null then raise exception 'MATCH_NOT_FOUND_OR_INVALID_TOKEN'; end if;
    if v_match.status not in ('live','in_progress') then raise exception 'MATCH_NOT_RUNNING'; end if;

    v_score1:=coalesce(v_match.score1,0)-case when v_event.player_slot=1 then v_event.score_delta else 0 end;
    v_score2:=coalesce(v_match.score2,0)-case when v_event.player_slot=2 then v_event.score_delta else 0 end;
    if v_score1<0 or v_score2<0 then raise exception 'UNDO_WOULD_CREATE_NEGATIVE_SCORE'; end if;

    update public.matches
    set score1=v_score1,score2=v_score2,updated_at=now()
    where id=v_match.id;

    update public.tournament_resource_assignments
    set score1=v_score1,score2=v_score2
    where match_id=v_match.id and released_at is null;

    update public.score_events
    set undone_at=now(),undone_by=auth.uid(),undo_reason=nullif(btrim(p_reason),'')
    where id=v_event.id;

    return jsonb_build_object(
      'event_id',v_event.id,'undone',true,'duplicate',false,
      'score1',v_score1,'score2',v_score2
    );
  end if;

  if auth.uid() is null then raise exception 'AUTHENTICATION_REQUIRED'; end if;

  select ts.* into v_session
  from public.training_sessions ts
  where ts.id=v_event.training_session_id
    and ts.owner_id=auth.uid()
  for update;

  if v_session.id is null then raise exception 'TRAINING_SESSION_NOT_FOUND_OR_ACCESS_DENIED'; end if;
  if v_session.status not in ('active','paused') then raise exception 'TRAINING_SESSION_NOT_RUNNING'; end if;

  v_scores:=coalesce(v_session.live_scores,array[0,0,0]::integer[]);
  v_scores[v_event.player_slot]:=coalesce(v_scores[v_event.player_slot],0)-v_event.score_delta;
  if v_scores[v_event.player_slot]<0 then raise exception 'UNDO_WOULD_CREATE_NEGATIVE_SCORE'; end if;

  update public.training_sessions
  set live_scores=v_scores,updated_at=now()
  where id=v_session.id;

  update public.score_events
  set undone_at=now(),undone_by=auth.uid(),undo_reason=nullif(btrim(p_reason),'')
  where id=v_event.id;

  return jsonb_build_object(
    'event_id',v_event.id,'undone',true,'duplicate',false,
    'live_scores',v_scores
  );
end;
$$;

revoke all on function public.undo_scoreboard_event(uuid,uuid,text) from public;
grant execute on function public.undo_scoreboard_event(uuid,uuid,text) to anon, authenticated;

create or replace view public.player_score_metric_totals
with (security_invoker=true)
as
select
  e.player_profile_id,
  e.sport,
  e.discipline,
  e.metric_key,
  sum(e.metric_value) as metric_total,
  count(*)::integer as event_count,
  max(e.created_at) as last_recorded_at
from public.score_events e
where e.undone_at is null
  and e.player_profile_id is not null
  and e.metric_key is not null
group by e.player_profile_id,e.sport,e.discipline,e.metric_key;

grant select on public.player_score_metric_totals to authenticated;

