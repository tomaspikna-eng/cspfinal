alter table public.tournament_calendar
  add column if not exists source_type text not null default 'tournament',
  add column if not exists event_id uuid,
  add column if not exists description text,
  add column if not exists event_type text,
  add column if not exists starts_at timestamptz,
  add column if not exists ends_at timestamptz,
  add column if not exists cover_image_url text,
  add column if not exists club_id uuid;

alter table public.tournament_calendar
  drop constraint if exists tournament_calendar_status_check,
  add constraint tournament_calendar_status_check
    check (status = any (array['draft'::text,'active'::text,'published'::text,'cancelled'::text,'completed'::text,'archived'::text]));

alter table public.tournament_calendar
  drop constraint if exists tournament_calendar_source_type_check,
  add constraint tournament_calendar_source_type_check
    check (source_type = any (array['tournament'::text,'event'::text]));

alter table public.tournament_calendar
  drop constraint if exists tournament_calendar_event_id_fkey,
  add constraint tournament_calendar_event_id_fkey
    foreign key (event_id) references public.events(id) on delete cascade;

alter table public.tournament_calendar
  drop constraint if exists tournament_calendar_club_id_fkey,
  add constraint tournament_calendar_club_id_fkey
    foreign key (club_id) references public.clubs(id) on delete set null;

create unique index if not exists tournament_calendar_event_id_uidx
  on public.tournament_calendar(event_id)
  where event_id is not null;

create index if not exists tournament_calendar_source_date_idx
  on public.tournament_calendar(source_type, event_date);

update public.tournament_calendar
set source_type='tournament'
where tournament_id is not null;

create or replace function public.sync_event_to_calendar()
returns trigger
language plpgsql
set search_path to 'public'
as $$
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
    'event', new.id, null, new.owner_id, new.club_id,
    new.title, new.description, new.event_type, new.sport, new.discipline, null,
    new.starts_at::date, new.starts_at, new.ends_at, new.location_text, new.city, null,
    (select p.full_name from public.profiles p where p.id = new.owner_id),
    new.visibility, new.registration_enabled, new.registration_deadline,
    new.max_participants, null, null, new.cover_image_url,
    new.status, new.created_at, new.updated_at
  )
  on conflict (event_id) where event_id is not null do update set
    source_type = 'event',
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
$$;

drop trigger if exists trg_sync_event_to_calendar on public.events;
create trigger trg_sync_event_to_calendar
after insert or update or delete on public.events
for each row execute function public.sync_event_to_calendar();

insert into public.tournament_calendar (
  source_type, event_id, tournament_id, owner_id, club_id,
  name, description, event_type, sport, discipline, format,
  event_date, starts_at, ends_at, venue, city, country,
  organizer_name, visibility, registration_enabled,
  registration_deadline, max_participants, external_url,
  public_slug, cover_image_url, status, created_at, updated_at
)
select
  'event', e.id, null, e.owner_id, e.club_id,
  e.title, e.description, e.event_type, e.sport, e.discipline, null,
  e.starts_at::date, e.starts_at, e.ends_at, e.location_text, e.city, null,
  p.full_name, e.visibility, e.registration_enabled,
  e.registration_deadline, e.max_participants, null,
  null, e.cover_image_url, e.status, e.created_at, e.updated_at
from public.events e
left join public.profiles p on p.id=e.owner_id
on conflict (event_id) where event_id is not null do update set
  owner_id=excluded.owner_id,
  club_id=excluded.club_id,
  name=excluded.name,
  description=excluded.description,
  event_type=excluded.event_type,
  sport=excluded.sport,
  discipline=excluded.discipline,
  event_date=excluded.event_date,
  starts_at=excluded.starts_at,
  ends_at=excluded.ends_at,
  venue=excluded.venue,
  city=excluded.city,
  organizer_name=excluded.organizer_name,
  visibility=excluded.visibility,
  registration_enabled=excluded.registration_enabled,
  registration_deadline=excluded.registration_deadline,
  max_participants=excluded.max_participants,
  cover_image_url=excluded.cover_image_url,
  status=excluded.status,
  updated_at=excluded.updated_at;

drop table if exists public.event_calendar cascade;

