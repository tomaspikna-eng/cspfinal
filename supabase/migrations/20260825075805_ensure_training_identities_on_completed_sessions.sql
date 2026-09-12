create or replace function public.ensure_completed_training_participants()
returns trigger
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare
  v_name text;
  v_slot int;
begin
  if new.status <> 'completed' then return new; end if;

  for v_slot in 1..least(coalesce(cardinality(new.player_names),0),3) loop
    v_name := nullif(btrim(new.player_names[v_slot]),'');
    if v_name is null then continue; end if;

    insert into public.training_session_participants(
      training_session_id,player_slot,player_id,display_name
    ) values (
      new.id,
      v_slot,
      case when v_slot=1 then new.owner_id else null end,
      v_name
    )
    on conflict (training_session_id,player_slot) do nothing;
  end loop;

  return new;
end;
$$;

drop trigger if exists trg_completed_training_participants on public.training_sessions;
create trigger trg_completed_training_participants
after insert or update of status
on public.training_sessions
for each row
when (new.status='completed')
execute function public.ensure_completed_training_participants();

