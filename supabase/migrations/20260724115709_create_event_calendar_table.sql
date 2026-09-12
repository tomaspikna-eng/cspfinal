create table if not exists public.event_calendar (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null unique references public.events(id) on delete cascade,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  club_id uuid references public.clubs(id) on delete set null,
  title text not null,
  description text,
  event_type text not null default 'Udalosť',
  sport text,
  discipline text,
  location_text text,
  city text,
  starts_at timestamptz not null,
  ends_at timestamptz,
  status text not null,
  visibility text not null default 'public',
  registration_enabled boolean not null default false,
  registration_deadline timestamptz,
  max_participants integer,
  cover_image_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists event_calendar_public_date_idx on public.event_calendar(visibility,status,starts_at);
create index if not exists event_calendar_city_type_idx on public.event_calendar(city,event_type,sport);
alter table public.event_calendar enable row level security;
drop policy if exists event_calendar_public_select on public.event_calendar;
create policy event_calendar_public_select on public.event_calendar for select to public using (visibility='public' and status='published');
drop policy if exists event_calendar_owner_select on public.event_calendar;
create policy event_calendar_owner_select on public.event_calendar for select to authenticated using (owner_id=auth.uid());

