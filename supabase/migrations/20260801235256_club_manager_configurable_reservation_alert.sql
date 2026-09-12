alter table public.clubs
  add column if not exists reservation_alert_minutes integer not null default 10;

alter table public.clubs
  drop constraint if exists clubs_reservation_alert_minutes_check;

alter table public.clubs
  add constraint clubs_reservation_alert_minutes_check
  check (reservation_alert_minutes between 0 and 1440);

create or replace function public.club_manager_set_reservation_alert_minutes(p_minutes integer)
returns integer
language plpgsql
security definer
set search_path to public, pg_temp
as $$
declare
  v_club_id uuid;
begin
  if p_minutes is null or p_minutes < 0 or p_minutes > 1440 then
    raise exception 'INVALID_ALERT_MINUTES';
  end if;

  select id into v_club_id
  from public.clubs
  where owner_id = auth.uid()
  order by created_at asc
  limit 1;

  if v_club_id is null and public.is_admin(auth.uid()) then
    select id into v_club_id
    from public.clubs
    order by created_at asc
    limit 1;
  end if;

  if v_club_id is null then
    raise exception 'CLUB_NOT_FOUND';
  end if;

  update public.clubs
  set reservation_alert_minutes = p_minutes,
      updated_at = now()
  where id = v_club_id;

  return p_minutes;
end;
$$;

grant execute on function public.club_manager_set_reservation_alert_minutes(integer) to authenticated;

create or replace function public.club_manager_bootstrap()
returns jsonb
language plpgsql
security definer
set search_path to public, pg_temp
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
    'club', case when v_club.id is null then null else jsonb_build_object(
      'id',v_club.id,
      'name',v_club.name,
      'reservation_alert_minutes',v_club.reservation_alert_minutes
    ) end
  );
end;
$$;

