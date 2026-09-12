
revoke execute on function public.record_training_score_event(uuid,smallint,text,numeric,text,text,text,numeric,jsonb) from anon;

create index score_events_action_definition_idx
  on public.score_events(action_definition_id);

create index score_events_tournament_player_idx
  on public.score_events(tournament_player_id)
  where tournament_player_id is not null;

create index score_events_training_participant_idx
  on public.score_events(training_participant_id)
  where training_participant_id is not null;

create index score_events_created_by_idx
  on public.score_events(created_by)
  where created_by is not null;

create index score_events_undone_by_idx
  on public.score_events(undone_by)
  where undone_by is not null;

create index training_session_participants_player_idx
  on public.training_session_participants(player_id)
  where player_id is not null;

