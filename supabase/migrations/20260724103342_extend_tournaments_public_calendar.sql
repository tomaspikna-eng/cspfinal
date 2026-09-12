alter table public.tournaments
  add column if not exists country text,
  add column if not exists city text,
  add column if not exists organizer_name text,
  add column if not exists visibility text not null default 'public',
  add column if not exists registration_enabled boolean not null default false,
  add column if not exists registration_deadline timestamptz,
  add column if not exists max_participants integer,
  add column if not exists external_url text,
  add column if not exists public_slug text;

alter table public.tournaments
  drop constraint if exists tournaments_visibility_check,
  add constraint tournaments_visibility_check
    check (visibility = any (array['public'::text,'private'::text,'unlisted'::text]));

alter table public.tournaments
  drop constraint if exists tournaments_max_participants_check,
  add constraint tournaments_max_participants_check
    check (max_participants is null or max_participants > 0);

create unique index if not exists tournaments_public_slug_uidx
  on public.tournaments(public_slug)
  where public_slug is not null;

create index if not exists tournaments_public_calendar_idx
  on public.tournaments(visibility, status, date);

create index if not exists tournaments_country_city_sport_idx
  on public.tournaments(country, city, sport);

update public.tournaments t
set organizer_name = p.full_name
from public.profiles p
where t.owner_id = p.id
  and t.organizer_name is null
  and nullif(trim(p.full_name),'') is not null;

drop policy if exists tournaments_select_published on public.tournaments;
create policy tournaments_select_published
on public.tournaments
for select
to public
using (
  status <> 'draft'
  and visibility in ('public','unlisted')
);

