alter table public.club_manager_live_sessions
  add column if not exists payment_method text,
  add column if not exists adjustment_amount numeric(10,2) not null default 0,
  add column if not exists adjustment_note text,
  add column if not exists final_amount numeric(10,2),
  add column if not exists reservation_customer_name text;

do $$ begin
  alter table public.club_manager_live_sessions add constraint club_manager_payment_method_check
    check (payment_method is null or payment_method in ('cash','card','invoice','other'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.club_manager_live_sessions add constraint club_manager_final_amount_check
    check (final_amount is null or final_amount >= 0);
exception when duplicate_object then null; end $$;

create unique index if not exists club_manager_one_active_session_per_station
  on public.club_manager_live_sessions(station_id)
  where station_id is not null and status in ('running','paused');

create or replace function public.club_manager_stop_session(p_session_id uuid)
returns public.club_manager_live_sessions
language plpgsql security definer set search_path='public','pg_temp'
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
      total_amount=v_total, final_amount=greatest(0,v_total+coalesce(adjustment_amount,0)), updated_at=now()
  where id=v.id returning * into v;
  update public.stations set status='idle', updated_at=now() where id=v.station_id;
  return v;
end $$;

create or replace function public.club_manager_adjust_session(
  p_session_id uuid,
  p_accumulated_seconds integer default null,
  p_adjustment_amount numeric default null,
  p_adjustment_note text default null
)
returns public.club_manager_live_sessions
language plpgsql security definer set search_path='public','pg_temp'
as $$
declare v public.club_manager_live_sessions; v_seconds integer; v_base numeric(10,2);
begin
  select ls.* into v from public.club_manager_live_sessions ls
  join public.clubs c on c.id=ls.club_id
  where ls.id=p_session_id and (c.owner_id=auth.uid() or public.is_admin(auth.uid()))
    and public.has_club_manager_access(auth.uid())
  for update of ls;
  if v.id is null then raise exception 'SESSION_NOT_FOUND'; end if;
  if v.status not in ('paused','stopped') then raise exception 'SESSION_MUST_BE_PAUSED_OR_STOPPED'; end if;
  v_seconds := coalesce(p_accumulated_seconds,v.accumulated_seconds);
  if v_seconds < 0 then raise exception 'INVALID_TIME'; end if;
  v_base := round(((v_seconds::numeric/3600) * v.hourly_rate * v.rate_multiplier)::numeric,2);
  update public.club_manager_live_sessions
  set accumulated_seconds=v_seconds,
      adjustment_amount=coalesce(p_adjustment_amount,adjustment_amount),
      adjustment_note=nullif(trim(coalesce(p_adjustment_note,adjustment_note)),''),
      total_amount=v_base,
      final_amount=greatest(0,v_base+coalesce(p_adjustment_amount,adjustment_amount,0)),
      updated_at=now()
  where id=v.id returning * into v;
  return v;
end $$;

create or replace function public.club_manager_settle_session(
  p_session_id uuid,
  p_payment_method text default 'cash',
  p_final_amount numeric default null
)
returns public.club_manager_live_sessions
language plpgsql security definer set search_path='public','pg_temp'
as $$
declare v public.club_manager_live_sessions; v_final numeric(10,2);
begin
  select ls.* into v from public.club_manager_live_sessions ls
  join public.clubs c on c.id=ls.club_id
  where ls.id=p_session_id and (c.owner_id=auth.uid() or public.is_admin(auth.uid()))
    and public.has_club_manager_access(auth.uid())
  for update of ls;
  if v.id is null then raise exception 'SESSION_NOT_FOUND'; end if;
  if v.status <> 'stopped' then raise exception 'SESSION_NOT_STOPPED'; end if;
  if p_payment_method not in ('cash','card','invoice','other') then raise exception 'INVALID_PAYMENT_METHOD'; end if;
  v_final := coalesce(p_final_amount,v.final_amount,v.total_amount,0);
  if v_final < 0 then raise exception 'INVALID_FINAL_AMOUNT'; end if;
  update public.club_manager_live_sessions
  set status='settled', payment_status='paid', payment_method=p_payment_method,
      final_amount=v_final, settled_at=now(), updated_at=now()
  where id=v.id returning * into v;
  return v;
end $$;

create or replace function public.club_manager_start_reservation(p_reservation_id uuid, p_price_profile_code text default 'walkin')
returns public.club_manager_live_sessions
language plpgsql security definer set search_path='public','pg_temp'
as $$
declare r public.reservations; s public.club_manager_live_sessions;
begin
  select x.* into r from public.reservations x
  join public.clubs c on c.id=x.club_id
  where x.id=p_reservation_id and (c.owner_id=auth.uid() or public.is_admin(auth.uid()))
    and public.has_club_manager_access(auth.uid())
  for update of x;
  if r.id is null then raise exception 'RESERVATION_NOT_FOUND'; end if;
  if r.station_id is null then raise exception 'RESERVATION_HAS_NO_STATION'; end if;
  if r.status not in ('pending','confirmed') then raise exception 'RESERVATION_NOT_STARTABLE'; end if;
  s := public.club_manager_start_session(r.station_id,p_price_profile_code);
  update public.club_manager_live_sessions set reservation_id=r.id,reservation_customer_name=r.customer_name where id=s.id returning * into s;
  update public.reservations set status='checked_in',checked_in_at=now(),updated_at=now() where id=r.id;
  return s;
end $$;

create or replace function public.club_manager_set_reservation_status(p_reservation_id uuid,p_status text)
returns public.reservations
language plpgsql security definer set search_path='public','pg_temp'
as $$
declare r public.reservations;
begin
  if p_status not in ('pending','confirmed','checked_in','completed','cancelled','no_show') then raise exception 'INVALID_STATUS'; end if;
  select x.* into r from public.reservations x join public.clubs c on c.id=x.club_id
  where x.id=p_reservation_id and (c.owner_id=auth.uid() or public.is_admin(auth.uid()))
    and public.has_club_manager_access(auth.uid()) for update of x;
  if r.id is null then raise exception 'RESERVATION_NOT_FOUND'; end if;
  update public.reservations set status=p_status,
    checked_in_at=case when p_status='checked_in' then coalesce(checked_in_at,now()) else checked_in_at end,
    completed_at=case when p_status='completed' then coalesce(completed_at,now()) else completed_at end,
    cancelled_at=case when p_status='cancelled' then coalesce(cancelled_at,now()) else cancelled_at end,
    cancelled_by=case when p_status='cancelled' then auth.uid() else cancelled_by end,
    updated_at=now() where id=r.id returning * into r;
  return r;
end $$;

create or replace function public.club_manager_upsert_reservation(
  p_reservation_id uuid,
  p_club_id uuid,
  p_station_id uuid,
  p_customer_name text,
  p_customer_email text,
  p_customer_phone text,
  p_party_size integer,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_internal_note text,
  p_status text default 'confirmed'
)
returns public.reservations
language plpgsql security definer set search_path='public','pg_temp'
as $$
declare r public.reservations; v_venue uuid;
begin
  if not public.has_club_manager_access(auth.uid()) then raise exception 'ACCESS_DENIED'; end if;
  if not exists(select 1 from public.clubs c where c.id=p_club_id and (c.owner_id=auth.uid() or public.is_admin(auth.uid()))) then raise exception 'ACCESS_DENIED'; end if;
  if p_status not in ('pending','confirmed') then raise exception 'INVALID_STATUS'; end if;
  if p_ends_at<=p_starts_at then raise exception 'INVALID_TIME_RANGE'; end if;
  select venue_id into v_venue from public.stations where id=p_station_id and club_id=p_club_id and is_active=true;
  if p_station_id is not null and v_venue is null then raise exception 'STATION_NOT_FOUND'; end if;
  if p_reservation_id is null then
    insert into public.reservations(club_id,venue_id,station_id,customer_name,customer_email,customer_phone,party_size,starts_at,ends_at,status,source,internal_note,created_by,station_name_snapshot,station_sport_snapshot)
    select p_club_id,v_venue,s.id,trim(p_customer_name),nullif(trim(p_customer_email),''),nullif(trim(p_customer_phone),''),p_party_size,p_starts_at,p_ends_at,p_status,'admin',nullif(trim(p_internal_note),''),auth.uid(),s.name,s.sport
    from public.stations s where s.id=p_station_id
    returning * into r;
  else
    update public.reservations x set venue_id=v_venue,station_id=p_station_id,customer_name=trim(p_customer_name),customer_email=nullif(trim(p_customer_email),''),customer_phone=nullif(trim(p_customer_phone),''),party_size=p_party_size,starts_at=p_starts_at,ends_at=p_ends_at,status=p_status,internal_note=nullif(trim(p_internal_note),''),updated_at=now(),station_name_snapshot=s.name,station_sport_snapshot=s.sport
    from public.stations s where x.id=p_reservation_id and x.club_id=p_club_id and s.id=p_station_id returning x.* into r;
  end if;
  if r.id is null then raise exception 'RESERVATION_SAVE_FAILED'; end if;
  return r;
exception when exclusion_violation then raise exception 'RESERVATION_OVERLAP';
end $$;

alter publication supabase_realtime add table public.club_manager_live_sessions;
alter publication supabase_realtime add table public.stations;
alter publication supabase_realtime add table public.reservations;

