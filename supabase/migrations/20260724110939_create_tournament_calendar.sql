create table if not exists public.tournament_calendar (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid unique references public.tournaments(id) on delete cascade,
  owner_id uuid references public.profiles(id) on delete set null,
  name text not null,
  sport text,
  discipline text,
  format text,
  event_date date,
  venue text,
  city text,
  country text,
  organizer_name text,
  visibility text not null default 'public' check (visibility in ('public','private','unlisted')),
  registration_enabled boolean not null default false,
  registration_deadline timestamptz,
  max_participants integer check (max_participants is null or max_participants > 0),
  external_url text,
  public_slug text,
  status text not null default 'active' check (status in ('draft','active','completed','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists tournament_calendar_public_slug_uidx
  on public.tournament_calendar(public_slug)
  where public_slug is not null;

create index if not exists tournament_calendar_public_idx
  on public.tournament_calendar(visibility,status,event_date);

create index if not exists tournament_calendar_filters_idx
  on public.tournament_calendar(country,city,sport,event_date);

alter table public.tournament_calendar enable row level security;

drop policy if exists tournament_calendar_public_select on public.tournament_calendar;
create policy tournament_calendar_public_select
on public.tournament_calendar
for select
to anon, authenticated
using (
  visibility = 'public'
  and status <> 'draft'
  and status <> 'archived'
);

drop policy if exists tournament_calendar_owner_all on public.tournament_calendar;
create policy tournament_calendar_owner_all
on public.tournament_calendar
for all
to authenticated
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

create or replace function public.sync_tournament_to_calendar()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    delete from public.tournament_calendar where tournament_id = old.id;
    return old;
  end if;

  insert into public.tournament_calendar (
    tournament_id, owner_id, name, sport, discipline, format, event_date,
    venue, city, country, organizer_name, visibility,
    registration_enabled, registration_deadline, max_participants,
    external_url, public_slug, status, updated_at
  ) values (
    new.id, new.owner_id, new.name, new.sport, new.discipline, new.format, new.date,
    new.venue, new.city, new.country, new.organizer_name, new.visibility,
    new.registration_enabled, new.registration_deadline, new.max_participants,
    new.external_url, new.public_slug, new.status, now()
  )
  on conflict (tournament_id) do update set
    owner_id = excluded.owner_id,
    name = excluded.name,
    sport = excluded.sport,
    discipline = excluded.discipline,
    format = excluded.format,
    event_date = excluded.event_date,
    venue = excluded.venue,
    city = excluded.city,
    country = excluded.country,
    organizer_name = excluded.organizer_name,
    visibility = excluded.visibility,
    registration_enabled = excluded.registration_enabled,
    registration_deadline = excluded.registration_deadline,
    max_participants = excluded.max_participants,
    external_url = excluded.external_url,
    public_slug = excluded.public_slug,
    status = excluded.status,
    updated_at = now();

  return new;
end;
$$;

drop trigger if exists trg_sync_tournament_to_calendar on public.tournaments;
create trigger trg_sync_tournament_to_calendar
after insert or update or delete on public.tournaments
for each row execute function public.sync_tournament_to_calendar();

insert into public.tournament_calendar (
  tournament_id, owner_id, name, sport, discipline, format, event_date,
  venue, city, country, organizer_name, visibility,
  registration_enabled, registration_deadline, max_participants,
  external_url, public_slug, status
)
select
  t.id, t.owner_id, t.name, t.sport, t.discipline, t.format, t.date,
  t.venue, t.city, t.country, t.organizer_name, t.visibility,
  t.registration_enabled, t.registration_deadline, t.max_participants,
  t.external_url, t.public_slug, t.status
from public.tournaments t
on conflict (tournament_id) do nothing;

