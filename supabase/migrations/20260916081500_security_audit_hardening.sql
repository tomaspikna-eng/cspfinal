-- Connect Sports Pro — security audit hardening 2026-09-16
-- Closes capability-token disclosure, profile PII exposure, unsafe match self-report
-- mutation surface, role=admin self-escalation and unrestricted image buckets.

-- ---------------------------------------------------------------------------
-- 1. Profiles: expose only public-safe columns through the base table.
--    Private data is available to the signed-in user through a narrow RPC.
-- ---------------------------------------------------------------------------

create or replace function public.get_my_profile_private()
returns table (
  id uuid,
  full_name text,
  email text,
  role public.profile_role,
  plan public.profile_plan,
  is_admin boolean,
  plan_updated_at timestamptz,
  plan_source text,
  avatar_url text,
  created_at timestamptz,
  updated_at timestamptz,
  tournaments_created_count integer,
  cover_url text,
  bio text,
  avatar_position_x numeric,
  avatar_position_y numeric,
  avatar_zoom numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    p.id, p.full_name, p.email, p.role, p.plan, p.is_admin,
    p.plan_updated_at, p.plan_source, p.avatar_url, p.created_at,
    p.updated_at, p.tournaments_created_count, p.cover_url, p.bio,
    p.avatar_position_x, p.avatar_position_y, p.avatar_zoom
  from public.profiles p
  where p.id = (select auth.uid());
$$;

revoke all on function public.get_my_profile_private() from public, anon;
grant execute on function public.get_my_profile_private() to authenticated, service_role;

create or replace function public.get_admin_profiles_private()
returns table (
  id uuid,
  full_name text,
  email text,
  role public.profile_role,
  plan public.profile_plan,
  is_admin boolean,
  plan_updated_at timestamptz,
  plan_source text,
  avatar_url text,
  created_at timestamptz,
  updated_at timestamptz,
  tournaments_created_count integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_admin((select auth.uid())) then
    raise exception 'ADMIN_REQUIRED';
  end if;

  return query
  select p.id, p.full_name, p.email, p.role, p.plan, p.is_admin,
         p.plan_updated_at, p.plan_source, p.avatar_url, p.created_at,
         p.updated_at, p.tournaments_created_count
  from public.profiles p
  order by p.created_at;
end;
$$;

revoke all on function public.get_admin_profiles_private() from public, anon;
grant execute on function public.get_admin_profiles_private() to authenticated, service_role;

create or replace function public.admin_set_profile_access(
  p_profile_id uuid,
  p_plan public.profile_plan default null,
  p_is_admin boolean default null,
  p_role public.profile_role default null
)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.profiles;
begin
  if not public.is_admin((select auth.uid()))
     and coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'ADMIN_REQUIRED';
  end if;

  if p_role = 'admin'::public.profile_role and coalesce(p_is_admin, false) is not true then
    raise exception 'ADMIN_ROLE_REQUIRES_ADMIN_FLAG';
  end if;

  update public.profiles p
  set plan = coalesce(p_plan, p.plan),
      is_admin = coalesce(p_is_admin, p.is_admin),
      role = coalesce(p_role, p.role),
      plan_source = case when p_plan is not null then 'admin' else p.plan_source end,
      plan_updated_at = case when p_plan is not null then now() else p.plan_updated_at end
  where p.id = p_profile_id
  returning p.* into v_row;

  if v_row.id is null then raise exception 'PROFILE_NOT_FOUND'; end if;
  return v_row;
end;
$$;

revoke all on function public.admin_set_profile_access(uuid, public.profile_plan, boolean, public.profile_role) from public, anon;
grant execute on function public.admin_set_profile_access(uuid, public.profile_plan, boolean, public.profile_role) to authenticated, service_role;

-- A normal user may choose player/club/organization, but must never self-assign
-- the admin role or any billing/admin-owned fields.
create or replace function public.protect_admin_only_columns()
returns trigger
language plpgsql
set search_path = 'public', 'pg_temp'
as $$
declare
  v_privileged boolean;
begin
  v_privileged := (auth.role() = 'service_role') or public.is_admin(auth.uid());

  if not v_privileged then
    new.plan := old.plan;
    new.is_admin := old.is_admin;
    new.plan_updated_at := old.plan_updated_at;
    new.plan_source := old.plan_source;
    new.tournaments_created_count := old.tournaments_created_count;
    new.created_at := old.created_at;
    new.email := old.email;
    if new.role = 'admin'::public.profile_role then
      new.role := old.role;
    end if;
  elsif new.plan is distinct from old.plan or new.plan_source is distinct from old.plan_source then
    new.plan_updated_at := now();
  end if;

  return new;
end;
$$;

-- Remove broad client privileges and explicitly expose only public-safe fields.
revoke all on table public.profiles from anon;
revoke select, delete, truncate, references, trigger on table public.profiles from authenticated;
revoke update on table public.profiles from authenticated;

grant select (
  id, full_name, role, plan, avatar_url, created_at, cover_url, bio,
  avatar_position_x, avatar_position_y, avatar_zoom
) on table public.profiles to anon, authenticated;

grant update (
  full_name, role, avatar_url, cover_url, bio,
  avatar_position_x, avatar_position_y, avatar_zoom
) on table public.profiles to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Capability tokens: never expose bearer secrets through spectator SELECTs.
--    Owner/tablet flows keep receiving them from already-authorized RPCs.
-- ---------------------------------------------------------------------------

do $acl$
declare
  v_columns text;
begin
  revoke select on table public.matches from authenticated;
  select string_agg(quote_ident(a.attname), ', ' order by a.attnum)
    into v_columns
  from pg_catalog.pg_attribute a
  where a.attrelid = 'public.matches'::regclass
    and a.attnum > 0 and not a.attisdropped
    and a.attname <> 'public_token';
  execute 'grant select (' || v_columns || ') on table public.matches to authenticated';

  revoke select on table public.tournament_resources from authenticated;
  select string_agg(quote_ident(a.attname), ', ' order by a.attnum)
    into v_columns
  from pg_catalog.pg_attribute a
  where a.attrelid = 'public.tournament_resources'::regclass
    and a.attnum > 0 and not a.attisdropped
    and a.attname <> 'device_token';
  execute 'grant select (' || v_columns || ') on table public.tournament_resources to authenticated';
end;
$acl$;

-- The anon scorer/station table grants were unnecessary: public capability
-- flows use SECURITY DEFINER RPCs, not direct table access.
revoke all on table public.tournament_scorers from anon;
revoke all on table public.stations from anon;

-- Rotate every bearer capability that may have been disclosed before this fix.
-- Existing paired tournament tablets must re-scan their QR once after release.
update public.matches set public_token = gen_random_uuid();
update public.tournament_resources
set device_token = gen_random_uuid(),
    tablet_paired_at = null,
    tablet_last_seen_at = null,
    updated_at = now();

-- ---------------------------------------------------------------------------
-- 3. Match self-report: future-proof the BEFORE UPDATE guard.
--    A participant can change only their own reported score; every other
--    field is restored from OLD automatically, including fields added later.
-- ---------------------------------------------------------------------------

create or replace function public.handle_match_self_report()
returns trigger
language plpgsql
security definer
set search_path = 'public'
as $$
declare
  v_owner_id uuid;
  v_privileged boolean;
  v_player1_user uuid;
  v_player2_user uuid;
  v_is_p1_reporter boolean;
  v_is_p2_reporter boolean;
  v_requested_p1_score integer;
  v_requested_p2_score integer;
begin
  select owner_id into v_owner_id
  from public.tournaments
  where id = old.tournament_id;

  v_privileged := public.is_admin(auth.uid()) or (v_owner_id = auth.uid());

  if not v_privileged then
    select user_id into v_player1_user from public.tournament_players where id = old.player1_id;
    select user_id into v_player2_user from public.tournament_players where id = old.player2_id;

    v_is_p1_reporter := v_player1_user is not null and v_player1_user = auth.uid();
    v_is_p2_reporter := v_player2_user is not null and v_player2_user = auth.uid();

    if not v_is_p1_reporter and not v_is_p2_reporter then
      raise exception 'MATCH_UPDATE_NOT_ALLOWED';
    end if;

    v_requested_p1_score := new.player1_reported_score;
    v_requested_p2_score := new.player2_reported_score;

    -- Critical: reset the complete row first. This makes the protection
    -- automatically cover current and future columns.
    new := old;

    if v_is_p1_reporter then
      if v_requested_p1_score is not null and v_requested_p1_score < 0 then
        raise exception 'INVALID_REPORTED_SCORE';
      end if;
      new.player1_reported_score := v_requested_p1_score;
      if v_requested_p1_score is distinct from old.player1_reported_score then
        new.player1_reported_at := now();
      end if;
    end if;

    if v_is_p2_reporter then
      if v_requested_p2_score is not null and v_requested_p2_score < 0 then
        raise exception 'INVALID_REPORTED_SCORE';
      end if;
      new.player2_reported_score := v_requested_p2_score;
      if v_requested_p2_score is distinct from old.player2_reported_score then
        new.player2_reported_at := now();
      end if;
    end if;
  end if;

  if new.player1_reported_score is distinct from old.player1_reported_score
     or new.player2_reported_score is distinct from old.player2_reported_score then
    if new.player1_reported_score is not null and new.player2_reported_score is not null then
      if new.player1_reported_score = new.player2_reported_score then
        new.status := 'disputed';
      else
        new.score1 := new.player1_reported_score;
        new.score2 := new.player2_reported_score;
        new.winner_id := case
          when new.player1_reported_score > new.player2_reported_score then new.player1_id
          else new.player2_id
        end;
        new.status := 'completed';
      end if;
    end if;
  end if;

  return new;
end;
$$;

revoke execute on function public.handle_match_self_report() from public, anon, authenticated;

create or replace function public.submit_match_self_report(p_match_id uuid, p_score integer)
returns public.matches
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_match public.matches;
  v_p1_user uuid;
  v_p2_user uuid;
begin
  if v_uid is null then raise exception 'AUTHENTICATION_REQUIRED'; end if;
  if p_score is null or p_score < 0 then raise exception 'INVALID_REPORTED_SCORE'; end if;

  select m.* into v_match from public.matches m where m.id = p_match_id for update;
  if v_match.id is null then raise exception 'MATCH_NOT_FOUND'; end if;
  if v_match.status in ('completed','forfeited','cancelled') then raise exception 'MATCH_IS_CLOSED'; end if;

  select tp.user_id into v_p1_user from public.tournament_players tp where tp.id = v_match.player1_id;
  select tp.user_id into v_p2_user from public.tournament_players tp where tp.id = v_match.player2_id;

  if v_p1_user = v_uid then
    update public.matches
    set player1_reported_score = p_score,
        player1_reported_at = now()
    where id = p_match_id
    returning * into v_match;
  elsif v_p2_user = v_uid then
    update public.matches
    set player2_reported_score = p_score,
        player2_reported_at = now()
    where id = p_match_id
    returning * into v_match;
  else
    raise exception 'PLAYER_NOT_ASSIGNED_TO_MATCH';
  end if;

  return v_match;
end;
$$;

revoke all on function public.submit_match_self_report(uuid, integer) from public, anon;
grant execute on function public.submit_match_self_report(uuid, integer) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. Storage: public buckets may contain images only and have hard size caps.
-- ---------------------------------------------------------------------------

update storage.buckets
set file_size_limit = 8388608,
    allowed_mime_types = array['image/jpeg','image/png','image/webp']::text[]
where id = 'avatars';

update storage.buckets
set file_size_limit = 8388608,
    allowed_mime_types = array['image/jpeg','image/png','image/webp']::text[]
where id = 'article-covers';

-- ---------------------------------------------------------------------------
-- 5. Audit-log ACL: clients can read permitted rows only; writes are internal.
-- ---------------------------------------------------------------------------

revoke all on table public.audit_logs from anon;
revoke insert, update, delete, truncate, references, trigger on table public.audit_logs from authenticated;
grant select on table public.audit_logs to authenticated;
