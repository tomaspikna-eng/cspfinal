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
    'profile', jsonb_build_object(
      'id', v_profile.id,
      'full_name', v_profile.full_name,
      'email', v_profile.email
    ),
    'club', case when v_club.id is null then null else jsonb_build_object(
      'id', v_club.id,
      'name', v_club.name,
      'reservation_alert_minutes', v_club.reservation_alert_minutes,
      'opening_hours', coalesce(v_club.opening_hours, '{}'::jsonb)
    ) end
  );
end;
$$;