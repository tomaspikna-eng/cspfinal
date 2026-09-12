begin;

create or replace function public.club_has_reservation_plan(p_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.clubs c
    join public.profiles p on p.id = c.owner_id
    where c.id = p_club_id
      and (p.plan in ('ultra'::public.profile_plan, 'elite'::public.profile_plan) or p.is_admin = true)
  );
$$;

revoke all on function public.club_has_reservation_plan(uuid) from public;
grant execute on function public.club_has_reservation_plan(uuid) to anon, authenticated;

create or replace function public.can_manage_club_reservations(p_club_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.can_manage_club(p_club_id)
     and public.club_has_reservation_plan(p_club_id);
$$;

revoke all on function public.can_manage_club_reservations(uuid) from public;
grant execute on function public.can_manage_club_reservations(uuid) to authenticated;

create or replace function public.get_public_club_booking_context(p_club_id uuid)
returns table (
  club_id uuid,
  club_name text,
  booking_enabled boolean,
  station_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select c.id,
         c.name,
         (
           public.club_has_reservation_plan(c.id)
           and coalesce(rs.public_booking_enabled, false)
         ) as booking_enabled,
         count(st.id) filter (where st.is_active = true) as station_count
  from public.clubs c
  left join public.reservation_settings rs on rs.club_id = c.id
  left join public.stations st on st.club_id = c.id
  where c.id = p_club_id
  group by c.id, c.name, rs.public_booking_enabled;
$$;

revoke all on function public.get_public_club_booking_context(uuid) from public;
grant execute on function public.get_public_club_booking_context(uuid) to anon, authenticated;

create or replace function public.get_public_booking_calendar(p_club_id uuid, p_day date)
returns table(station_id uuid, station_name text, sport text, base_hourly_rate numeric, starts_at timestamptz, ends_at timestamptz, state text)
language sql
stable
security definer
set search_path = public
as $$
  with settings as (
    select rs.timezone as tz,
           rs.slot_minutes
    from public.reservation_settings rs
    where rs.club_id = p_club_id
      and rs.public_booking_enabled = true
      and public.club_has_reservation_plan(p_club_id)
  ), hours as (
    select oh.opens_at, oh.closes_at, oh.is_closed, s.tz, s.slot_minutes
    from settings s
    join public.reservation_opening_hours oh
      on oh.club_id = p_club_id
     and oh.day_of_week = extract(dow from p_day)::int
  ), slots as (
    select generate_series(
      (p_day + h.opens_at) at time zone h.tz,
      ((p_day + h.closes_at) at time zone h.tz) - make_interval(mins => h.slot_minutes),
      make_interval(mins => h.slot_minutes)
    ) as slot_start,
    h.slot_minutes
    from hours h
    where h.is_closed = false
  )
  select st.id,
         st.name,
         st.sport,
         st.base_hourly_rate,
         sl.slot_start,
         sl.slot_start + make_interval(mins => sl.slot_minutes),
         case
           when exists (
             select 1 from public.reservations r
             where r.station_id = st.id
               and r.status in ('pending','confirmed','checked_in')
               and tstzrange(r.starts_at,r.ends_at,'[)') && tstzrange(sl.slot_start,sl.slot_start+make_interval(mins=>sl.slot_minutes),'[)')
           ) then 'occupied'
           when exists (
             select 1 from public.reservation_blocks b
             where b.club_id = p_club_id
               and (b.station_id is null or b.station_id = st.id)
               and tstzrange(b.starts_at,b.ends_at,'[)') && tstzrange(sl.slot_start,sl.slot_start+make_interval(mins=>sl.slot_minutes),'[)')
           ) then 'blocked'
           else 'available'
         end
  from public.stations st
  cross join slots sl
  where st.club_id = p_club_id
    and st.is_active = true
  order by st.sort_order, st.name, sl.slot_start;
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
returns table(reservation_id uuid, public_token uuid, status text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_settings public.reservation_settings%rowtype;
  v_row public.reservations%rowtype;
begin
  if not public.club_has_reservation_plan(p_club_id) then
    raise exception 'Reservation feature is not available for this club';
  end if;

  select * into v_settings
  from public.reservation_settings
  where club_id = p_club_id;

  if not found or not v_settings.public_booking_enabled then
    raise exception 'Public booking is disabled';
  end if;

  if p_ends_at <= p_starts_at then
    raise exception 'Invalid reservation interval';
  end if;

  if p_starts_at < now() + make_interval(mins => v_settings.min_notice_minutes) then
    raise exception 'Reservation is too soon';
  end if;

  if p_starts_at > now() + make_interval(days => v_settings.booking_horizon_days) then
    raise exception 'Reservation is outside booking horizon';
  end if;

  if extract(epoch from (p_ends_at-p_starts_at))/60 < v_settings.min_duration_minutes then
    raise exception 'Reservation is too short';
  end if;

  if extract(epoch from (p_ends_at-p_starts_at))/60 > v_settings.max_duration_minutes then
    raise exception 'Reservation is too long';
  end if;

  insert into public.reservations(
    club_id, venue_id, station_id, customer_profile_id,
    customer_name, customer_email, customer_phone, party_size,
    starts_at, ends_at, status, source, public_note
  )
  select p_club_id, s.venue_id, p_station_id, auth.uid(),
         trim(p_customer_name), nullif(trim(p_customer_email),''), nullif(trim(p_customer_phone),''), p_party_size,
         p_starts_at, p_ends_at,
         case when v_settings.requires_confirmation then 'pending' else 'confirmed' end,
         'public', p_public_note
  from public.stations s
  where s.id = p_station_id
    and s.club_id = p_club_id
    and s.is_active = true
  returning * into v_row;

  if v_row.id is null then
    raise exception 'Station not found';
  end if;

  return query select v_row.id, v_row.public_token, v_row.status;
end;
$$;

revoke all on function public.create_public_reservation(uuid,uuid,timestamptz,timestamptz,text,text,text,integer,text) from public;
grant execute on function public.create_public_reservation(uuid,uuid,timestamptz,timestamptz,text,text,text,integer,text) to anon, authenticated;

alter policy reservation_settings_admin_all on public.reservation_settings
  using (public.can_manage_club_reservations(club_id))
  with check (public.can_manage_club_reservations(club_id));

alter policy opening_hours_admin_all on public.reservation_opening_hours
  using (public.can_manage_club_reservations(club_id))
  with check (public.can_manage_club_reservations(club_id));

alter policy reservations_admin_all on public.reservations
  using (public.can_manage_club_reservations(club_id))
  with check (public.can_manage_club_reservations(club_id));

alter policy reservation_blocks_admin_all on public.reservation_blocks
  using (public.can_manage_club_reservations(club_id))
  with check (public.can_manage_club_reservations(club_id));

commit;

