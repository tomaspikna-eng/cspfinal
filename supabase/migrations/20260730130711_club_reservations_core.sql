create extension if not exists btree_gist with schema extensions;

create table if not exists public.reservation_settings (
  club_id uuid primary key references public.clubs(id) on delete cascade,
  public_booking_enabled boolean not null default true,
  requires_confirmation boolean not null default true,
  slot_minutes integer not null default 60 check (slot_minutes in (15,30,45,60,90,120)),
  min_duration_minutes integer not null default 60 check (min_duration_minutes > 0),
  max_duration_minutes integer not null default 240 check (max_duration_minutes >= min_duration_minutes),
  booking_horizon_days integer not null default 30 check (booking_horizon_days between 1 and 365),
  min_notice_minutes integer not null default 60 check (min_notice_minutes >= 0),
  cancellation_notice_minutes integer not null default 120 check (cancellation_notice_minutes >= 0),
  timezone text not null default 'Europe/Bratislava',
  public_note text,
  terms_text text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.reservation_opening_hours (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  day_of_week integer not null check (day_of_week between 0 and 6),
  opens_at time,
  closes_at time,
  is_closed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (club_id, day_of_week),
  check (is_closed or (opens_at is not null and closes_at is not null and closes_at > opens_at))
);

create table if not exists public.reservations (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  venue_id uuid references public.venues(id) on delete set null,
  station_id uuid not null references public.stations(id) on delete restrict,
  customer_profile_id uuid references public.profiles(id) on delete set null,
  customer_name text not null check (char_length(trim(customer_name)) between 2 and 120),
  customer_email text,
  customer_phone text,
  party_size integer check (party_size is null or party_size > 0),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'pending' check (status in ('pending','confirmed','checked_in','completed','cancelled','no_show')),
  source text not null default 'public' check (source in ('public','admin','profile','phone','walk_in')),
  public_note text,
  internal_note text,
  quoted_amount numeric(10,2) check (quoted_amount is null or quoted_amount >= 0),
  currency text not null default 'EUR' check (char_length(currency)=3),
  public_token uuid not null default gen_random_uuid() unique,
  checked_in_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  cancelled_by uuid references public.profiles(id) on delete set null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create table if not exists public.reservation_blocks (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  venue_id uuid references public.venues(id) on delete set null,
  station_id uuid references public.stations(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  block_type text not null default 'manual' check (block_type in ('manual','service','tournament','private_event','closed')),
  title text not null,
  note text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create index if not exists reservations_club_time_idx on public.reservations(club_id, starts_at, ends_at);
create index if not exists reservations_station_time_idx on public.reservations(station_id, starts_at, ends_at);
create index if not exists reservations_public_token_idx on public.reservations(public_token);
create index if not exists reservation_blocks_club_time_idx on public.reservation_blocks(club_id, starts_at, ends_at);
create index if not exists reservation_blocks_station_time_idx on public.reservation_blocks(station_id, starts_at, ends_at);

alter table public.reservations drop constraint if exists reservations_no_overlap;
alter table public.reservations add constraint reservations_no_overlap
exclude using gist (
  station_id with =,
  tstzrange(starts_at, ends_at, '[)') with &&
) where (status in ('pending','confirmed','checked_in'));

alter table public.reservation_blocks drop constraint if exists reservation_blocks_no_overlap;
alter table public.reservation_blocks add constraint reservation_blocks_no_overlap
exclude using gist (
  station_id with =,
  tstzrange(starts_at, ends_at, '[)') with &&
) where (station_id is not null);

create or replace function public.can_manage_club(p_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.clubs c
    join public.profiles p on p.id = auth.uid()
    where c.id = p_club_id and (c.owner_id = auth.uid() or p.is_admin)
  );
$$;

create or replace function public.validate_reservation_relations()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.stations s where s.id = new.station_id and s.club_id = new.club_id) then
    raise exception 'Station does not belong to club';
  end if;
  if new.venue_id is not null and not exists (select 1 from public.venues v where v.id = new.venue_id and v.club_id = new.club_id) then
    raise exception 'Venue does not belong to club';
  end if;
  if exists (
    select 1 from public.reservation_blocks b
    where b.club_id = new.club_id
      and (b.station_id is null or b.station_id = new.station_id)
      and tstzrange(b.starts_at,b.ends_at,'[)') && tstzrange(new.starts_at,new.ends_at,'[)')
  ) then
    raise exception 'Requested time is blocked';
  end if;
  return new;
end;
$$;

drop trigger if exists validate_reservation_relations_trigger on public.reservations;
create trigger validate_reservation_relations_trigger
before insert or update of club_id,venue_id,station_id,starts_at,ends_at,status
on public.reservations
for each row
when (new.status in ('pending','confirmed','checked_in'))
execute function public.validate_reservation_relations();

create or replace function public.validate_block_conflicts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.station_id is not null and not exists (select 1 from public.stations s where s.id = new.station_id and s.club_id = new.club_id) then
    raise exception 'Station does not belong to club';
  end if;
  if new.venue_id is not null and not exists (select 1 from public.venues v where v.id = new.venue_id and v.club_id = new.club_id) then
    raise exception 'Venue does not belong to club';
  end if;
  if exists (
    select 1 from public.reservations r
    where r.club_id = new.club_id
      and r.status in ('pending','confirmed','checked_in')
      and (new.station_id is null or r.station_id = new.station_id)
      and tstzrange(r.starts_at,r.ends_at,'[)') && tstzrange(new.starts_at,new.ends_at,'[)')
  ) then
    raise exception 'Block overlaps an active reservation';
  end if;
  return new;
end;
$$;

drop trigger if exists validate_block_conflicts_trigger on public.reservation_blocks;
create trigger validate_block_conflicts_trigger
before insert or update of club_id,venue_id,station_id,starts_at,ends_at
on public.reservation_blocks
for each row execute function public.validate_block_conflicts();

create or replace function public.touch_reservation_updated_at()
returns trigger language plpgsql as $$ begin new.updated_at = now(); return new; end $$;

drop trigger if exists touch_reservation_settings on public.reservation_settings;
create trigger touch_reservation_settings before update on public.reservation_settings for each row execute function public.touch_reservation_updated_at();
drop trigger if exists touch_reservation_opening_hours on public.reservation_opening_hours;
create trigger touch_reservation_opening_hours before update on public.reservation_opening_hours for each row execute function public.touch_reservation_updated_at();
drop trigger if exists touch_reservations on public.reservations;
create trigger touch_reservations before update on public.reservations for each row execute function public.touch_reservation_updated_at();
drop trigger if exists touch_reservation_blocks on public.reservation_blocks;
create trigger touch_reservation_blocks before update on public.reservation_blocks for each row execute function public.touch_reservation_updated_at();

alter table public.reservation_settings enable row level security;
alter table public.reservation_opening_hours enable row level security;
alter table public.reservations enable row level security;
alter table public.reservation_blocks enable row level security;

drop policy if exists reservation_settings_admin_all on public.reservation_settings;
create policy reservation_settings_admin_all on public.reservation_settings for all to authenticated using (public.can_manage_club(club_id)) with check (public.can_manage_club(club_id));
drop policy if exists opening_hours_admin_all on public.reservation_opening_hours;
create policy opening_hours_admin_all on public.reservation_opening_hours for all to authenticated using (public.can_manage_club(club_id)) with check (public.can_manage_club(club_id));
drop policy if exists reservations_admin_all on public.reservations;
create policy reservations_admin_all on public.reservations for all to authenticated using (public.can_manage_club(club_id)) with check (public.can_manage_club(club_id));
drop policy if exists reservations_customer_read on public.reservations;
create policy reservations_customer_read on public.reservations for select to authenticated using (customer_profile_id = auth.uid());
drop policy if exists reservation_blocks_admin_all on public.reservation_blocks;
create policy reservation_blocks_admin_all on public.reservation_blocks for all to authenticated using (public.can_manage_club(club_id)) with check (public.can_manage_club(club_id));

create or replace function public.get_public_booking_calendar(p_club_id uuid, p_day date)
returns table (
  station_id uuid,
  station_name text,
  sport text,
  base_hourly_rate numeric,
  starts_at timestamptz,
  ends_at timestamptz,
  state text
)
language sql
stable
security definer
set search_path = public
as $$
  with settings as (
    select coalesce(rs.timezone,'Europe/Bratislava') as tz,
           coalesce(rs.slot_minutes,60) as slot_minutes
    from public.clubs c
    left join public.reservation_settings rs on rs.club_id=c.id
    where c.id=p_club_id and coalesce(rs.public_booking_enabled,true)
  ), hours as (
    select oh.opens_at, oh.closes_at, oh.is_closed, s.tz, s.slot_minutes
    from settings s
    left join public.reservation_opening_hours oh
      on oh.club_id=p_club_id and oh.day_of_week=extract(dow from p_day)::int
  ), slots as (
    select generate_series(
      (p_day + coalesce(h.opens_at,time '08:00')) at time zone h.tz,
      ((p_day + coalesce(h.closes_at,time '22:00')) at time zone h.tz) - make_interval(mins=>h.slot_minutes),
      make_interval(mins=>h.slot_minutes)
    ) as slot_start,
    h.slot_minutes
    from hours h where coalesce(h.is_closed,false)=false
  )
  select st.id, st.name, st.sport, st.base_hourly_rate,
         sl.slot_start,
         sl.slot_start + make_interval(mins=>sl.slot_minutes),
         case
           when exists (select 1 from public.reservations r where r.station_id=st.id and r.status in ('pending','confirmed','checked_in') and tstzrange(r.starts_at,r.ends_at,'[)') && tstzrange(sl.slot_start,sl.slot_start+make_interval(mins=>sl.slot_minutes),'[)')) then 'occupied'
           when exists (select 1 from public.reservation_blocks b where b.club_id=p_club_id and (b.station_id is null or b.station_id=st.id) and tstzrange(b.starts_at,b.ends_at,'[)') && tstzrange(sl.slot_start,sl.slot_start+make_interval(mins=>sl.slot_minutes),'[)')) then 'blocked'
           else 'available'
         end
  from public.stations st
  cross join slots sl
  where st.club_id=p_club_id and st.is_active=true
  order by st.sort_order,st.name,sl.slot_start;
$$;

create or replace function public.create_public_reservation(
  p_club_id uuid,
  p_station_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_customer_name text,
  p_customer_email text default null,
  p_customer_phone text default null,
  p_party_size integer default null,
  p_public_note text default null
)
returns table (reservation_id uuid, public_token uuid, status text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_settings public.reservation_settings%rowtype;
  v_row public.reservations%rowtype;
begin
  select * into v_settings from public.reservation_settings where club_id=p_club_id;
  if found and not v_settings.public_booking_enabled then raise exception 'Public booking is disabled'; end if;
  if p_starts_at < now() + make_interval(mins=>coalesce(v_settings.min_notice_minutes,60)) then raise exception 'Reservation is too soon'; end if;
  if p_starts_at > now() + make_interval(days=>coalesce(v_settings.booking_horizon_days,30)) then raise exception 'Reservation is outside booking horizon'; end if;
  if extract(epoch from (p_ends_at-p_starts_at))/60 < coalesce(v_settings.min_duration_minutes,60) then raise exception 'Reservation is too short'; end if;
  if extract(epoch from (p_ends_at-p_starts_at))/60 > coalesce(v_settings.max_duration_minutes,240) then raise exception 'Reservation is too long'; end if;
  insert into public.reservations(club_id,venue_id,station_id,customer_profile_id,customer_name,customer_email,customer_phone,party_size,starts_at,ends_at,status,source,public_note)
  select p_club_id,s.venue_id,p_station_id,auth.uid(),trim(p_customer_name),nullif(trim(p_customer_email),''),nullif(trim(p_customer_phone),''),p_party_size,p_starts_at,p_ends_at,case when coalesce(v_settings.requires_confirmation,true) then 'pending' else 'confirmed' end,'public',p_public_note
  from public.stations s where s.id=p_station_id and s.club_id=p_club_id and s.is_active=true
  returning * into v_row;
  if v_row.id is null then raise exception 'Station not found'; end if;
  return query select v_row.id,v_row.public_token,v_row.status;
end;
$$;

create or replace function public.get_public_reservation(p_public_token uuid)
returns table (
  reservation_id uuid,
  club_id uuid,
  station_name text,
  starts_at timestamptz,
  ends_at timestamptz,
  status text,
  customer_name text,
  public_note text,
  quoted_amount numeric,
  currency text
)
language sql
stable
security definer
set search_path = public
as $$
  select r.id,r.club_id,s.name,r.starts_at,r.ends_at,r.status,r.customer_name,r.public_note,r.quoted_amount,r.currency
  from public.reservations r join public.stations s on s.id=r.station_id
  where r.public_token=p_public_token;
$$;

create or replace function public.cancel_public_reservation(p_public_token uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare v_res public.reservations%rowtype; v_notice integer;
begin
  select * into v_res from public.reservations where public_token=p_public_token for update;
  if not found then return false; end if;
  if v_res.status not in ('pending','confirmed') then return false; end if;
  select coalesce(cancellation_notice_minutes,120) into v_notice from public.reservation_settings where club_id=v_res.club_id;
  if v_res.starts_at < now()+make_interval(mins=>coalesce(v_notice,120)) then return false; end if;
  update public.reservations set status='cancelled',cancelled_at=now(),cancelled_by=auth.uid() where id=v_res.id;
  return true;
end;
$$;

grant execute on function public.get_public_booking_calendar(uuid,date) to anon,authenticated;
grant execute on function public.create_public_reservation(uuid,uuid,timestamptz,timestamptz,text,text,text,integer,text) to anon,authenticated;
grant execute on function public.get_public_reservation(uuid) to anon,authenticated;
grant execute on function public.cancel_public_reservation(uuid) to anon,authenticated;

alter table public.club_manager_live_sessions add column if not exists reservation_id uuid references public.reservations(id) on delete set null;
create index if not exists club_manager_live_sessions_reservation_idx on public.club_manager_live_sessions(reservation_id);

