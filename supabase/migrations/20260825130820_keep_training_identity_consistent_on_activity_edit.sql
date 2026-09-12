create or replace function public.edit_my_training_activity(
  p_session_id uuid,
  p_sport text,
  p_discipline text,
  p_player1_name text,
  p_player2_name text,
  p_score1 integer,
  p_score2 integer,
  p_occurred_at timestamptz,
  p_duration_seconds integer
)
returns public.training_sessions
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v public.training_sessions;
  v_before jsonb;
  v_winner text;
  v_name1 text;
  v_name2 text;
  v_sport text;
  v_discipline text;
  v_score1 integer;
  v_score2 integer;
  v_duration integer;
  v_identity1 public.player_identities;
  v_identity2 public.player_identities;
begin
  if auth.uid() is null then
    raise exception 'AUTHENTICATION_REQUIRED';
  end if;

  select * into v
  from public.training_sessions
  where id=p_session_id and owner_id=auth.uid()
  for update;

  if v.id is null then
    raise exception 'TRAINING_SESSION_NOT_FOUND_OR_ACCESS_DENIED';
  end if;

  if v.status not in ('completed','archived') then
    raise exception 'ONLY_FINISHED_TRAINING_CAN_BE_EDITED';
  end if;

  v_before:=to_jsonb(v);
  v_name1:=left(coalesce(nullif(btrim(p_player1_name),''),coalesce(v.player_names[1],'Hráč 1')),160);
  v_name2:=left(coalesce(nullif(btrim(p_player2_name),''),coalesce(v.player_names[2],'Hráč 2')),160);
  v_sport:=left(coalesce(nullif(btrim(p_sport),''),v.sport),80);
  v_discipline:=left(coalesce(nullif(btrim(p_discipline),''),v.discipline),120);
  v_score1:=greatest(coalesce(p_score1,0),0);
  v_score2:=greatest(coalesce(p_score2,0),0);
  v_duration:=greatest(coalesce(p_duration_seconds,coalesce(v.duration_seconds,v.elapsed_seconds,0)),0);

  if v_score1>v_score2 then v_winner:=v_name1;
  elsif v_score2>v_score1 then v_winner:=v_name2;
  else v_winner:=null;
  end if;

  v_identity1:=public.resolve_or_create_player_identity(v_name1,auth.uid(),'training_activity_edit');
  v_identity2:=public.resolve_or_create_player_identity(v_name2,null,'training_activity_edit');

  update public.training_sessions
  set sport=v_sport,
      discipline=v_discipline,
      player_names=array[v_name1,v_name2],
      live_scores=array[v_score1,v_score2,0],
      final_score=jsonb_build_object(
        'mode','frame',
        'players',jsonb_build_array(
          jsonb_build_object('name',v_name1,'score',v_score1),
          jsonb_build_object('name',v_name2,'score',v_score2)
        )
      ),
      winner_name=v_winner,
      duration_seconds=v_duration,
      elapsed_seconds=v_duration,
      played_at=coalesce(p_occurred_at,played_at),
      completed_at=case when status='completed' then coalesce(p_occurred_at,completed_at) else completed_at end,
      archived_at=case when status='archived' then coalesce(p_occurred_at,archived_at) else archived_at end,
      updated_at=now()
  where id=p_session_id
  returning * into v;

  update public.training_session_participants
  set display_name=case player_slot when 1 then v_name1 when 2 then v_name2 else display_name end,
      player_id=case when player_slot=1 then auth.uid() else null end,
      player_identity_id=case when player_slot=1 then v_identity1.id when player_slot=2 then v_identity2.id else player_identity_id end
  where training_session_id=p_session_id and player_slot in (1,2);

  insert into public.audit_logs(user_id,entity_type,entity_id,action,metadata)
  values(auth.uid(),'training_session',p_session_id,'activity_edited',jsonb_build_object('before',v_before,'after',to_jsonb(v)));

  return v;
end;
$function$;

