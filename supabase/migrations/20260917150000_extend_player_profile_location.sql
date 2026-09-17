-- Adds a real player location to the PRO+ profile header.
-- The profile owner already has an authenticated owner-only UPDATE policy.

alter table public.profiles
  add column if not exists city text,
  add column if not exists country_code text;

alter table public.profiles
  drop constraint if exists profiles_city_length,
  add constraint profiles_city_length
    check (city is null or char_length(city) <= 100),
  drop constraint if exists profiles_country_code_format,
  add constraint profiles_country_code_format
    check (country_code is null or country_code ~ '^[A-Z]{2}$');

comment on column public.profiles.city is
  'Player city displayed in authenticated profile dashboards.';

comment on column public.profiles.country_code is
  'ISO 3166-1 alpha-2 country code used for the player country label and flag.';

create or replace function public.get_my_pro_plus_dashboard()
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_profile jsonb;
  v_location jsonb;
  v_achievements jsonb;
  v_ihs jsonb;
  v_gear jsonb;
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  if not public.has_plan_at_least(v_user_id, 'pro_plus') then
    raise exception 'PRO+ plan required' using errcode = '42501';
  end if;

  v_profile := public.get_my_player_profile_dashboard();

  select jsonb_build_object('city', p.city, 'country_code', p.country_code)
  into v_location
  from public.profiles p
  where p.id = v_user_id;

  v_profile := jsonb_set(
    coalesce(v_profile, '{}'::jsonb),
    '{profile}',
    coalesce(v_profile->'profile', '{}'::jsonb) || coalesce(v_location, '{}'::jsonb),
    true
  );

  v_achievements := public.get_my_achievements();
  v_ihs := public.get_my_ihs_overview();

  select jsonb_build_object(
    'board_name', g.board_name,
    'equipment_name', g.equipment_name,
    'motto', g.motto,
    'updated_at', g.updated_at
  )
  into v_gear
  from public.player_gear g
  where g.user_id = v_user_id;

  return v_profile || jsonb_build_object(
    'achievements', coalesce(v_achievements, '{}'::jsonb),
    'ihs', coalesce(v_ihs, '{}'::jsonb),
    'gear', coalesce(v_gear, jsonb_build_object(
      'board_name', null,
      'equipment_name', null,
      'motto', null,
      'updated_at', null
    ))
  );
end;
$$;

revoke all on function public.get_my_pro_plus_dashboard() from public, anon;
grant execute on function public.get_my_pro_plus_dashboard() to authenticated, service_role;
