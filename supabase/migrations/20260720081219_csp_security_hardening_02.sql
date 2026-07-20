-- CSP security hardening 02
revoke execute on function public.can_access_magazine_cms(uuid) from anon;
revoke execute on function public.can_create_tournament(uuid) from anon;
revoke execute on function public.current_plan(uuid) from anon;
revoke execute on function public.has_feature_access(uuid,text) from anon;
revoke execute on function public.has_plan_at_least(uuid,text) from anon;
revoke execute on function public.is_admin(uuid) from anon;
revoke execute on function public.remaining_tournament_quota(uuid) from anon;

-- Public buckets remain public for direct object URLs. Listing through PostgREST is removed.
drop policy if exists article_covers_select_public on storage.objects;
drop policy if exists avatars_select_public on storage.objects;
