begin;

-- Public and unlisted published events may be opened by direct link.
-- Private events remain visible only to their owner through events_owner_all.
drop policy if exists events_select_published on public.events;
drop policy if exists events_select_public_or_unlisted on public.events;

create policy events_select_public_or_unlisted
  on public.events
  for select
  to anon, authenticated
  using (
    status = 'published'
    and visibility in ('public','unlisted')
  );

create or replace function public.submit_event_preregistration(
  p_event_id uuid,
  p_full_name text,
  p_nickname text,
  p_consent boolean
) returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_event public.events%rowtype;
  v_id uuid;
  v_count integer;
  v_user_id uuid;
begin
  select * into v_event
  from public.events
  where id = p_event_id;

  if not found then raise exception 'Udalosť neexistuje.'; end if;

  if v_event.status <> 'published'
     or v_event.visibility not in ('public','unlisted') then
    raise exception 'Predregistrácia nie je dostupná.';
  end if;

  if not coalesce(v_event.registration_enabled, false) then
    raise exception 'Predregistrácia nie je zapnutá.';
  end if;

  if v_event.registration_deadline is not null and now() > v_event.registration_deadline then
    raise exception 'Predregistrácia už bola ukončená.';
  end if;

  if coalesce(trim(p_full_name), '') = '' then raise exception 'Zadaj meno a priezvisko.'; end if;
  if coalesce(trim(p_nickname), '') = '' then raise exception 'Zadaj nickname.'; end if;

  if length(trim(p_full_name)) > 120 or length(trim(p_nickname)) > 60 then
    raise exception 'Zadané údaje sú príliš dlhé.';
  end if;

  if not p_consent then
    raise exception 'Na odoslanie je potrebný súhlas so spracovaním údajov.';
  end if;

  if v_event.max_participants is not null then
    select count(*) into v_count
    from public.event_preregistrations
    where event_id = p_event_id;

    if v_count >= v_event.max_participants then
      raise exception 'Kapacita predregistrácie je naplnená.';
    end if;
  end if;

  select p.id into v_user_id
  from public.profiles p
  where p.id = auth.uid();

  insert into public.event_preregistrations(event_id, full_name, nickname, consent_given, user_id)
  values (p_event_id, trim(p_full_name), trim(p_nickname), true, v_user_id)
  returning id into v_id;

  return v_id;
exception
  when unique_violation then
    raise exception 'Tento nickname je už pre túto udalosť zaregistrovaný.';
end;
$function$;

create or replace function public.get_public_event_preregistrations(p_event_id uuid)
returns table (
  nickname text,
  created_at timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select r.nickname, r.created_at
  from public.event_preregistrations r
  join public.events e on e.id = r.event_id
  where r.event_id = p_event_id
    and e.status = 'published'
    and e.visibility in ('public','unlisted')
    and e.registration_enabled = true
  order by r.created_at asc;
$$;

commit;