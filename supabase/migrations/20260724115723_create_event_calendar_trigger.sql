create or replace function public.sync_event_to_calendar()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    delete from public.event_calendar where event_id = old.id;
    return old;
  end if;

  insert into public.event_calendar (
    event_id, owner_id, club_id, title, description, event_type,
    sport, discipline, location_text, city, starts_at, ends_at,
    status, visibility, registration_enabled, registration_deadline,
    max_participants, cover_image_url, created_at, updated_at
  ) values (
    new.id, new.owner_id, new.club_id, new.title, new.description, new.event_type,
    new.sport, new.discipline, new.location_text, new.city, new.starts_at, new.ends_at,
    new.status, new.visibility, new.registration_enabled, new.registration_deadline,
    new.max_participants, new.cover_image_url, new.created_at, new.updated_at
  )
  on conflict (event_id) do update set
    owner_id = excluded.owner_id,
    club_id = excluded.club_id,
    title = excluded.title,
    description = excluded.description,
    event_type = excluded.event_type,
    sport = excluded.sport,
    discipline = excluded.discipline,
    location_text = excluded.location_text,
    city = excluded.city,
    starts_at = excluded.starts_at,
    ends_at = excluded.ends_at,
    status = excluded.status,
    visibility = excluded.visibility,
    registration_enabled = excluded.registration_enabled,
    registration_deadline = excluded.registration_deadline,
    max_participants = excluded.max_participants,
    cover_image_url = excluded.cover_image_url,
    updated_at = excluded.updated_at;

  return new;
end;
$$;

drop trigger if exists trg_sync_event_to_calendar on public.events;
create trigger trg_sync_event_to_calendar
after insert or update or delete on public.events
for each row execute function public.sync_event_to_calendar();

