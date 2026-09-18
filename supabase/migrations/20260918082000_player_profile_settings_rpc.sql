-- Secure player self-service profile settings.
-- Browser clients must not update public.profiles directly after profile hardening.

create or replace function public.update_my_player_profile_settings(p_patch jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.profiles;
  v_country text;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'invalid profile patch' using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_object_keys(p_patch) k
    where k not in (
      'full_name','bio','avatar_url','city','country_code',
      'avatar_position_x','avatar_position_y','avatar_zoom'
    )
  ) then
    raise exception 'unsupported profile field' using errcode = '22023';
  end if;

  v_country := upper(nullif(trim(p_patch->>'country_code'),''));
  if v_country is not null and v_country !~ '^[A-Z]{2}$' then
    raise exception 'country_code must be ISO 3166-1 alpha-2' using errcode = '22023';
  end if;

  update public.profiles p
  set
    full_name = case when p_patch ? 'full_name'
      then nullif(trim(p_patch->>'full_name'),'') else p.full_name end,
    bio = case when p_patch ? 'bio'
      then nullif(trim(p_patch->>'bio'),'') else p.bio end,
    avatar_url = case when p_patch ? 'avatar_url'
      then nullif(trim(p_patch->>'avatar_url'),'') else p.avatar_url end,
    city = case when p_patch ? 'city'
      then nullif(trim(p_patch->>'city'),'') else p.city end,
    country_code = case when p_patch ? 'country_code'
      then v_country else p.country_code end,
    avatar_position_x = case when p_patch ? 'avatar_position_x'
      then greatest(0,least(100,coalesce((p_patch->>'avatar_position_x')::numeric,p.avatar_position_x))) else p.avatar_position_x end,
    avatar_position_y = case when p_patch ? 'avatar_position_y'
      then greatest(0,least(100,coalesce((p_patch->>'avatar_position_y')::numeric,p.avatar_position_y))) else p.avatar_position_y end,
    avatar_zoom = case when p_patch ? 'avatar_zoom'
      then greatest(1,least(3,coalesce((p_patch->>'avatar_zoom')::numeric,p.avatar_zoom))) else p.avatar_zoom end
  where p.id = v_uid
  returning p.* into v_row;

  if v_row.id is null then
    raise exception 'profile not found' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'id',v_row.id,
    'full_name',v_row.full_name,
    'role',v_row.role,
    'plan',v_row.plan,
    'avatar_url',v_row.avatar_url,
    'bio',v_row.bio,
    'city',v_row.city,
    'country_code',v_row.country_code,
    'avatar_position_x',v_row.avatar_position_x,
    'avatar_position_y',v_row.avatar_position_y,
    'avatar_zoom',v_row.avatar_zoom
  );
end;
$$;

revoke all on function public.update_my_player_profile_settings(jsonb) from public, anon;
grant execute on function public.update_my_player_profile_settings(jsonb) to authenticated, service_role;
