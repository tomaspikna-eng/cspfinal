create table if not exists public.club_public_profiles (
  club_id uuid primary key references public.clubs(id) on delete cascade,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  about_title text,
  about_text text,
  offer_text text,
  contact_text text,
  history_text text,
  photo_url text,
  status text not null default 'draft' check (status in ('draft','published','hidden')),
  reservations_visible boolean not null default true,
  events_visible boolean not null default true,
  representatives_visible boolean not null default true,
  gallery_visible boolean not null default true,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_id)
);

create table if not exists public.club_representatives (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  item_type text not null default 'player' check (item_type in ('player','team')),
  name text not null,
  discipline text,
  bio text,
  achievements text,
  photo_url text,
  status text not null default 'draft' check (status in ('draft','published','hidden')),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.club_public_profiles enable row level security;
alter table public.club_representatives enable row level security;

drop policy if exists club_public_profiles_owner_all on public.club_public_profiles;
create policy club_public_profiles_owner_all on public.club_public_profiles
for all using (owner_id = auth.uid() or public.is_admin(auth.uid()))
with check (owner_id = auth.uid() or public.is_admin(auth.uid()));

drop policy if exists club_public_profiles_public_read on public.club_public_profiles;
create policy club_public_profiles_public_read on public.club_public_profiles
for select using (status = 'published');

drop policy if exists club_representatives_owner_all on public.club_representatives;
create policy club_representatives_owner_all on public.club_representatives
for all using (owner_id = auth.uid() or public.is_admin(auth.uid()))
with check (owner_id = auth.uid() or public.is_admin(auth.uid()));

drop policy if exists club_representatives_public_read on public.club_representatives;
create policy club_representatives_public_read on public.club_representatives
for select using (status = 'published');

create or replace function public.set_public_profile_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

drop trigger if exists club_public_profiles_set_updated_at on public.club_public_profiles;
create trigger club_public_profiles_set_updated_at before update on public.club_public_profiles
for each row execute function public.set_public_profile_updated_at();

drop trigger if exists club_representatives_set_updated_at on public.club_representatives;
create trigger club_representatives_set_updated_at before update on public.club_representatives
for each row execute function public.set_public_profile_updated_at();

