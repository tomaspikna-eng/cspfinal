begin;

alter table public.events
  add column if not exists event_type text,
  add column if not exists cover_image_url text,
  add column if not exists city text,
  add column if not exists visibility text not null default 'public',
  add column if not exists registration_enabled boolean not null default false,
  add column if not exists registration_deadline timestamptz,
  add column if not exists max_participants integer,
  add column if not exists published_at timestamptz;

update public.events
set event_type = coalesce(nullif(trim(discipline), ''), 'Udalosť')
where event_type is null or trim(event_type) = '';

alter table public.events
  alter column event_type set default 'Udalosť',
  alter column event_type set not null;

alter table public.events drop constraint if exists events_status_check;
alter table public.events
  add constraint events_status_check
  check (status = any (array['draft'::text,'published'::text,'cancelled'::text,'completed'::text]));

alter table public.events drop constraint if exists events_visibility_check;
alter table public.events
  add constraint events_visibility_check
  check (visibility = any (array['public'::text,'unlisted'::text,'private'::text]));

alter table public.events drop constraint if exists events_max_participants_check;
alter table public.events
  add constraint events_max_participants_check
  check (max_participants is null or max_participants > 0);

alter table public.events drop constraint if exists events_registration_deadline_check;
alter table public.events
  add constraint events_registration_deadline_check
  check (registration_deadline is null or registration_deadline <= starts_at);

create index if not exists events_public_calendar_idx
  on public.events (starts_at asc)
  where status = 'published' and visibility = 'public';

create index if not exists events_owner_calendar_idx
  on public.events (owner_id, starts_at desc);

create index if not exists events_club_calendar_idx
  on public.events (club_id, starts_at desc)
  where club_id is not null;

create or replace function public.events_set_publish_timestamps()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  if new.status = 'published' and (old.status is distinct from 'published' or old.published_at is null) then
    new.published_at := coalesce(old.published_at, now());
  end if;
  return new;
end;
$$;

drop trigger if exists trg_events_set_publish_timestamps on public.events;
create trigger trg_events_set_publish_timestamps
before update on public.events
for each row execute function public.events_set_publish_timestamps();

update public.events
set published_at = coalesce(published_at, created_at)
where status = 'published';

comment on column public.events.event_type is 'Human-readable event type shown in calendar widgets, e.g. Turnaj, Liga, Tréning, Exhibícia.';
comment on column public.events.cover_image_url is 'Optional event cover image URL/path. Calendar widgets may remain text-first and use the image only on detail pages.';
comment on column public.events.visibility is 'public = landing/profile calendar; unlisted = direct-link only; private = owner only.';
comment on column public.events.city is 'City displayed in event detail and optional calendar filters.';

create or replace function public.get_public_event_calendar(p_limit integer default 12)
returns table (
  id uuid,
  club_name text,
  event_type text,
  title text,
  sport text,
  discipline text,
  starts_at timestamptz,
  ends_at timestamptz,
  city text,
  location_text text,
  cover_image_url text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    e.id,
    coalesce(c.name, p.full_name, 'Connect Sports Pro') as club_name,
    e.event_type,
    e.title,
    e.sport,
    e.discipline,
    e.starts_at,
    e.ends_at,
    e.city,
    e.location_text,
    e.cover_image_url
  from public.events e
  left join public.clubs c on c.id = e.club_id
  left join public.profiles p on p.id = e.owner_id
  where e.status = 'published'
    and e.visibility = 'public'
    and e.starts_at >= now()
  order by e.starts_at asc
  limit greatest(1, least(coalesce(p_limit, 12), 50));
$$;

revoke all on function public.get_public_event_calendar(integer) from public;
grant execute on function public.get_public_event_calendar(integer) to anon, authenticated;

commit;

