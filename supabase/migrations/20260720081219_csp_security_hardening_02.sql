-- Restrict direct anonymous access to privileged helper RPCs.
revoke execute on function public.can_access_magazine_cms(uuid) from anon;
revoke execute on function public.can_create_tournament(uuid) from anon;
revoke execute on function public.current_plan(uuid) from anon;
revoke execute on function public.has_feature_access(uuid,text) from anon;
revoke execute on function public.has_plan_at_least(uuid,text) from anon;
revoke execute on function public.is_admin(uuid) from anon;
revoke execute on function public.remaining_tournament_quota(uuid) from anon;

-- Keep only the intentionally public token lookup callable anonymously.
grant execute on function public.get_station_by_token(text) to anon, authenticated;

-- Public buckets do not need broad SELECT policies for public object URLs.
drop policy if exists article_covers_select_public on storage.objects;
drop policy if exists avatars_select_public on storage.objects;

-- Harden search_path on all exposed SECURITY DEFINER helpers.
alter function public.can_access_magazine_cms(uuid) set search_path = public, pg_temp;
alter function public.can_create_tournament(uuid) set search_path = public, pg_temp;
alter function public.current_plan(uuid) set search_path = public, pg_temp;
alter function public.get_station_by_token(text) set search_path = public, pg_temp;
alter function public.has_feature_access(uuid,text) set search_path = public, pg_temp;
alter function public.has_plan_at_least(uuid,text) set search_path = public, pg_temp;
alter function public.is_admin(uuid) set search_path = public, pg_temp;
alter function public.remaining_tournament_quota(uuid) set search_path = public, pg_temp;

