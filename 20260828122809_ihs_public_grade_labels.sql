create or replace function public.ihs_grade_for_level(p_level text)
returns text
language sql
immutable
as $$
  select case lower(coalesce(p_level,''))
    when 'world_class' then 'A+'
    when 'elite' then 'A'
    when 'competitive' then 'B'
    when 'amateur' then 'C'
    else 'C'
  end;
$$;

create or replace function public.get_public_ihs_grade(p_player_id uuid, p_sport text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_sport text;
  v_rating public.player_ihs_ratings;
  v_profile public.player_ihs_profiles;
begin
  if p_player_id is null then
    raise exception 'Player id is required';
  end if;

  if not exists(select 1 from public.profiles p where p.id=p_player_id and p.role::text='player') then
    raise exception 'Player not found';
  end if;

  v_sport := nullif(btrim(p_sport),'');
  if v_sport is null then
    select pd.sport into v_sport
    from public.player_disciplines pd
    where pd.player_id=p_player_id
    order by pd.is_primary desc, pd.created_at asc
    limit 1;
  end if;

  v_profile := public.ensure_player_ihs_profile(p_player_id);

  if v_sport is not null then
    v_rating := public.ensure_player_ihs_rating(p_player_id,v_sport);
  end if;

  return jsonb_build_object(
    'player_id',p_player_id,
    'sport',coalesce(v_rating.sport,v_sport),
    'grade',public.ihs_grade_for_level(coalesce(v_rating.level,public.ihs_level_for_rating(v_profile.default_rating)))
  );
end;
$$;

revoke all on function public.get_public_ihs_grade(uuid,text) from public;
grant execute on function public.get_public_ihs_grade(uuid,text) to anon, authenticated;

create or replace function public.check_tournament_ihs_eligibility(p_tournament_id uuid, p_player_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_sport text;
  v_allowed text[];
  v_rating public.player_ihs_ratings;
  v_can_see_number boolean := false;
begin
  select sport, ihs_allowed_categories into v_sport, v_allowed
  from public.tournaments where id = p_tournament_id;

  if not found then
    raise exception 'Tournament not found';
  end if;

  v_rating := public.ensure_player_ihs_rating(p_player_id, v_sport);
  v_can_see_number := auth.uid() = p_player_id or public.is_admin(auth.uid());

  return jsonb_build_object(
    'eligible', v_rating.level = any(v_allowed),
    'rating', case when v_can_see_number then v_rating.rating else null end,
    'level', v_rating.level,
    'grade', public.ihs_grade_for_level(v_rating.level),
    'sport', v_rating.sport,
    'verified_matches', case when v_can_see_number then v_rating.verified_matches else null end,
    'allowed_categories', to_jsonb(v_allowed)
  );
end;
$$;

create or replace function public.validate_tournament_player_ihs()
returns trigger
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_profile_id uuid;
  v_sport text;
  v_allowed text[];
  v_rating public.player_ihs_ratings;
begin
  v_profile_id := public.resolve_tournament_player_profile_id(new.user_id, new.player_identity_id);
  if v_profile_id is null then return new; end if;

  select sport, ihs_allowed_categories into v_sport, v_allowed
  from public.tournaments where id = new.tournament_id;

  if v_sport is null then return new; end if;

  v_rating := public.ensure_player_ihs_rating(v_profile_id, v_sport);

  if not (v_rating.level = any(v_allowed)) then
    raise exception using
      errcode = '23514',
      message = format('CSP IHS: hráč má triedu %s, ktorá nie je povolená pre tento turnaj.', public.ihs_grade_for_level(v_rating.level));
  end if;

  return new;
end;
$$;

-- Numeric IHS development data is private to the player/admin. Public UI uses get_public_ihs_grade().
drop policy if exists player_ihs_ratings_read on public.player_ihs_ratings;
create policy player_ihs_ratings_read_own
on public.player_ihs_ratings
for select
using (player_id = auth.uid() or public.is_admin(auth.uid()));

create or replace function public.get_ihs_player_directory(p_sport text)
returns table(player_id uuid, full_name text, avatar_url text, ihs_rating numeric, ihs_level text, ihs_verified_matches integer, ihs_handicap jsonb)
language sql
security definer
set search_path to 'public','pg_temp'
as $$
  with base as (
    select p.id, p.full_name, p.avatar_url,
           coalesce(ip.default_rating, 2.50)::numeric as default_rating
    from public.profiles p
    left join public.player_ihs_profiles ip on ip.player_id = p.id
    where p.role::text = 'player' and p.full_name is not null
  )
  select b.id,
         b.full_name,
         b.avatar_url,
         null::numeric as ihs_rating,
         coalesce(r.level, public.ihs_level_for_rating(b.default_rating)),
         0::integer as ihs_verified_matches,
         '{}'::jsonb as ihs_handicap
  from base b
  left join public.player_ihs_ratings r
    on r.player_id = b.id
   and r.sport_key = public.normalize_ihs_sport(p_sport)
  order by b.full_name;
$$;

