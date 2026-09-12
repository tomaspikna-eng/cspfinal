update public.tournament_calendar
set source_type = 'tournament'
where source_type is distinct from 'tournament';

create or replace function public.sync_event_to_calendar()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
  if tg_op = 'DELETE' then
    delete from public.tournament_calendar where event_id = old.id;
    return old;
  end if;

  insert into public.tournament_calendar (
    source_type, event_id, tournament_id, owner_id, club_id,
    name, description, event_type, sport, discipline, format,
    event_date, starts_at, ends_at, venue, city, country,
    organizer_name, visibility, registration_enabled,
    registration_deadline, max_participants, external_url,
    public_slug, cover_image_url, status, created_at, updated_at
  ) values (
    'tournament', new.id, null, new.owner_id, new.club_id,
    new.title, new.description, new.event_type, new.sport, new.discipline, null,
    new.starts_at::date, new.starts_at, new.ends_at, new.location_text, new.city, null,
    (select p.full_name from public.profiles p where p.id = new.owner_id),
    new.visibility, new.registration_enabled, new.registration_deadline,
    new.max_participants, null, null, new.cover_image_url,
    new.status, new.created_at, new.updated_at
  )
  on conflict (event_id) where event_id is not null do update set
    source_type = 'tournament',
    owner_id = excluded.owner_id,
    club_id = excluded.club_id,
    name = excluded.name,
    description = excluded.description,
    event_type = excluded.event_type,
    sport = excluded.sport,
    discipline = excluded.discipline,
    event_date = excluded.event_date,
    starts_at = excluded.starts_at,
    ends_at = excluded.ends_at,
    venue = excluded.venue,
    city = excluded.city,
    organizer_name = excluded.organizer_name,
    visibility = excluded.visibility,
    registration_enabled = excluded.registration_enabled,
    registration_deadline = excluded.registration_deadline,
    max_participants = excluded.max_participants,
    cover_image_url = excluded.cover_image_url,
    status = excluded.status,
    updated_at = excluded.updated_at;

  return new;
end;
$function$;

alter table public.tournament_calendar
  drop constraint if exists tournament_calendar_source_type_check;

alter table public.tournament_calendar
  add constraint tournament_calendar_source_type_check
  check (source_type = 'tournament');

