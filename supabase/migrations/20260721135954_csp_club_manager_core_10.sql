create or replace function public.has_club_manager_access(p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = p_user_id
      and (p.is_admin = true or p.plan::text in ('ultra','elite'))
  );
$$;

revoke all on function public.has_club_manager_access(uuid) from public;
grant execute on function public.has_club_manager_access(uuid) to authenticated;

alter table public.venues
  add column if not exists is_active boolean not null default true;

alter table public.stations
  add column if not exists venue_id uuid references public.venues(id) on delete set null,
  add column if not exists status text not null default 'idle',
  add column if not exists base_hourly_rate numeric(10,2) not null default 0,
  add column if not exists sort_order integer not null default 0,
  add column if not exists is_active boolean not null default true;

alter table public.stations drop constraint if exists stations_status_check;
alter table public.stations add constraint stations_status_check
  check (status in ('idle','running','stopped','reserved','blocked','service','tournament'));

create table if not exists public.club_manager_price_profiles (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  code text not null,
  name text not null,
  rate_multiplier numeric(8,4) not null default 1,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (club_id, code),
  check (rate_multiplier > 0)
);

create table if not exists public.club_manager_live_sessions (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  station_id uuid not null references public.stations(id) on delete restrict,
  price_profile_id uuid references public.club_manager_price_profiles(id) on delete set null,
  customer_type text not null default 'walkin',
  status text not null default 'running',
  started_at timestamptz not null default now(),
  paused_at timestamptz,
  stopped_at timestamptz,
  accumulated_seconds integer not null default 0,
  hourly_rate numeric(10,2) not null,
  rate_multiplier numeric(8,4) not null default 1,
  total_amount numeric(10,2),
  payment_status text not null default 'unpaid',
  settled_at timestamptz,
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (status in ('running','paused','stopped','settled','cancelled')),
  check (payment_status in ('unpaid','paid','cancelled')),
  check (accumulated_seconds >= 0),
  check (hourly_rate >= 0),
  check (rate_multiplier > 0)
);

create unique index if not exists club_manager_one_open_session_per_station
  on public.club_manager_live_sessions(station_id)
  where status in ('running','paused','stopped');

create index if not exists club_manager_live_sessions_club_status_idx
  on public.club_manager_live_sessions(club_id, status);

alter table public.club_manager_price_profiles enable row level security;
alter table public.club_manager_live_sessions enable row level security;

drop policy if exists club_manager_price_profiles_owner_all on public.club_manager_price_profiles;
create policy club_manager_price_profiles_owner_all
on public.club_manager_price_profiles
for all to authenticated
using (
  public.has_club_manager_access(auth.uid()) and exists (
    select 1 from public.clubs c
    where c.id = club_manager_price_profiles.club_id
      and (c.owner_id = auth.uid() or public.is_admin(auth.uid()))
  )
)
with check (
  public.has_club_manager_access(auth.uid()) and exists (
    select 1 from public.clubs c
    where c.id = club_manager_price_profiles.club_id
      and (c.owner_id = auth.uid() or public.is_admin(auth.uid()))
  )
);

drop policy if exists club_manager_live_sessions_owner_all on public.club_manager_live_sessions;
create policy club_manager_live_sessions_owner_all
on public.club_manager_live_sessions
for all to authenticated
using (
  public.has_club_manager_access(auth.uid()) and exists (
    select 1 from public.clubs c
    where c.id = club_manager_live_sessions.club_id
      and (c.owner_id = auth.uid() or public.is_admin(auth.uid()))
  )
)
with check (
  public.has_club_manager_access(auth.uid()) and exists (
    select 1 from public.clubs c
    where c.id = club_manager_live_sessions.club_id
      and (c.owner_id = auth.uid() or public.is_admin(auth.uid()))
  )
);

create or replace function public.club_manager_bootstrap()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_profile public.profiles;
  v_club public.clubs;
begin
  select * into v_profile from public.profiles where id = auth.uid();
  if v_profile.id is null then
    raise exception 'PROFILE_NOT_FOUND';
  end if;
  if not public.has_club_manager_access(auth.uid()) then
    return jsonb_build_object(
      'allowed', false,
      'plan', v_profile.plan::text,
      'is_admin', v_profile.is_admin
    );
  end if;
  select * into v_club
  from public.clubs
  where owner_id = auth.uid()
  order by created_at asc
  limit 1;
  return jsonb_build_object(
    'allowed', true,
    'plan', v_profile.plan::text,
    'is_admin', v_profile.is_admin,
    'profile', jsonb_build_object('id',v_profile.id,'full_name',v_profile.full_name,'email',v_profile.email),
    'club', case when v_club.id is null then null else jsonb_build_object('id',v_club.id,'name',v_club.name) end
  );
end;
$$;

grant execute on function public.club_manager_bootstrap() to authenticated;

create or replace function public.club_manager_start_session(
  p_station_id uuid,
  p_price_profile_code text default 'walkin'
)
returns public.club_manager_live_sessions
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_station public.stations;
  v_club public.clubs;
  v_profile public.club_manager_price_profiles;
  v_session public.club_manager_live_sessions;
begin
  if not public.has_club_manager_access(auth.uid()) then raise exception 'ACCESS_DENIED'; end if;
  select s.* into v_station from public.stations s where s.id = p_station_id for update;
  if v_station.id is null then raise exception 'STATION_NOT_FOUND'; end if;
  select c.* into v_club from public.clubs c where c.id=v_station.club_id and (c.owner_id=auth.uid() or public.is_admin(auth.uid()));
  if v_club.id is null then raise exception 'ACCESS_DENIED'; end if;
  if v_station.status not in ('idle','reserved') then raise exception 'STATION_NOT_AVAILABLE'; end if;
  select * into v_profile from public.club_manager_price_profiles
   where club_id=v_station.club_id and code=p_price_profile_code and is_active=true limit 1;
  insert into public.club_manager_live_sessions(
    club_id, station_id, price_profile_id, customer_type, status,
    hourly_rate, rate_multiplier
  ) values (
    v_station.club_id, v_station.id, v_profile.id,
    coalesce(v_profile.code,p_price_profile_code), 'running',
    v_station.base_hourly_rate, coalesce(v_profile.rate_multiplier,1)
  ) returning * into v_session;
  update public.stations set status='running', updated_at=now() where id=v_station.id;
  return v_session;
end;
$$;

grant execute on function public.club_manager_start_session(uuid,text) to authenticated;

create or replace function public.club_manager_pause_session(p_session_id uuid)
returns public.club_manager_live_sessions
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v public.club_manager_live_sessions; v_elapsed integer;
begin
  select ls.* into v from public.club_manager_live_sessions ls
  join public.clubs c on c.id=ls.club_id
  where ls.id=p_session_id and (c.owner_id=auth.uid() or public.is_admin(auth.uid()))
    and public.has_club_manager_access(auth.uid())
  for update of ls;
  if v.id is null then raise exception 'SESSION_NOT_FOUND'; end if;
  if v.status <> 'running' then raise exception 'SESSION_NOT_RUNNING'; end if;
  v_elapsed := greatest(0, floor(extract(epoch from (now()-v.started_at)))::integer);
  update public.club_manager_live_sessions
  set status='paused', paused_at=now(), accumulated_seconds=accumulated_seconds+v_elapsed, updated_at=now()
  where id=v.id returning * into v;
  return v;
end;
$$;

grant execute on function public.club_manager_pause_session(uuid) to authenticated;

create or replace function public.club_manager_resume_session(p_session_id uuid)
returns public.club_manager_live_sessions
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v public.club_manager_live_sessions;
begin
  select ls.* into v from public.club_manager_live_sessions ls
  join public.clubs c on c.id=ls.club_id
  where ls.id=p_session_id and (c.owner_id=auth.uid() or public.is_admin(auth.uid()))
    and public.has_club_manager_access(auth.uid())
  for update of ls;
  if v.id is null then raise exception 'SESSION_NOT_FOUND'; end if;
  if v.status <> 'paused' then raise exception 'SESSION_NOT_PAUSED'; end if;
  update public.club_manager_live_sessions
  set status='running', started_at=now(), paused_at=null, updated_at=now()
  where id=v.id returning * into v;
  return v;
end;
$$;

grant execute on function public.club_manager_resume_session(uuid) to authenticated;

create or replace function public.club_manager_stop_session(p_session_id uuid)
returns public.club_manager_live_sessions
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v public.club_manager_live_sessions; v_seconds integer; v_total numeric(10,2);
begin
  select ls.* into v from public.club_manager_live_sessions ls
  join public.clubs c on c.id=ls.club_id
  where ls.id=p_session_id and (c.owner_id=auth.uid() or public.is_admin(auth.uid()))
    and public.has_club_manager_access(auth.uid())
  for update of ls;
  if v.id is null then raise exception 'SESSION_NOT_FOUND'; end if;
  if v.status not in ('running','paused') then raise exception 'SESSION_NOT_ACTIVE'; end if;
  v_seconds := v.accumulated_seconds + case when v.status='running' then greatest(0,floor(extract(epoch from (now()-v.started_at)))::integer) else 0 end;
  v_total := round(((v_seconds::numeric/3600) * v.hourly_rate * v.rate_multiplier)::numeric, 2);
  update public.club_manager_live_sessions
  set status='stopped', stopped_at=now(), accumulated_seconds=v_seconds,
      total_amount=v_total, updated_at=now()
  where id=v.id returning * into v;
  update public.stations set status='stopped', updated_at=now() where id=v.station_id;
  return v;
end;
$$;

grant execute on function public.club_manager_stop_session(uuid) to authenticated;

create or replace function public.club_manager_settle_session(p_session_id uuid)
returns public.club_manager_live_sessions
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v public.club_manager_live_sessions;
begin
  select ls.* into v from public.club_manager_live_sessions ls
  join public.clubs c on c.id=ls.club_id
  where ls.id=p_session_id and (c.owner_id=auth.uid() or public.is_admin(auth.uid()))
    and public.has_club_manager_access(auth.uid())
  for update of ls;
  if v.id is null then raise exception 'SESSION_NOT_FOUND'; end if;
  if v.status <> 'stopped' then raise exception 'SESSION_NOT_STOPPED'; end if;
  update public.club_manager_live_sessions
  set status='settled', payment_status='paid', settled_at=now(), updated_at=now()
  where id=v.id returning * into v;
  update public.stations set status='idle', updated_at=now() where id=v.station_id;
  return v;
end;
$$;

grant execute on function public.club_manager_settle_session(uuid) to authenticated;

insert into public.club_manager_price_profiles(club_id,code,name,rate_multiplier,sort_order)
select c.id, x.code, x.name, x.multiplier, x.ord
from public.clubs c
cross join (values
 ('walkin','Walk-in',1.0::numeric,1),
 ('vip','VIP',0.8::numeric,2),
 ('member','Člen',0.65::numeric,3)
) as x(code,name,multiplier,ord)
on conflict (club_id,code) do nothing;

