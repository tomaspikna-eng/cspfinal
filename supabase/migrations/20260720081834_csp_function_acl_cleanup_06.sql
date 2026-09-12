revoke execute on function public.can_access_magazine_cms(uuid) from public;
revoke execute on function public.can_create_tournament(uuid) from public;
revoke execute on function public.current_plan(uuid) from public;
revoke execute on function public.has_feature_access(uuid,text) from public;
revoke execute on function public.has_plan_at_least(uuid,text) from public;
revoke execute on function public.is_admin(uuid) from public;
revoke execute on function public.remaining_tournament_quota(uuid) from public;

grant execute on function public.can_access_magazine_cms(uuid) to authenticated;
grant execute on function public.can_create_tournament(uuid) to authenticated;
grant execute on function public.current_plan(uuid) to authenticated;
grant execute on function public.has_feature_access(uuid,text) to authenticated;
grant execute on function public.has_plan_at_least(uuid,text) to authenticated;
grant execute on function public.is_admin(uuid) to authenticated;
grant execute on function public.remaining_tournament_quota(uuid) to authenticated;

-- get_station_by_token is intentionally public because the station token page is public.
grant execute on function public.get_station_by_token(text) to public,anon,authenticated;

