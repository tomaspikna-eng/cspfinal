
alter table public.training_session_participants
  drop constraint if exists training_session_participants_training_session_id_player_id_key;

create unique index training_session_participants_linked_player_uq
  on public.training_session_participants(training_session_id,player_id)
  where player_id is not null;

