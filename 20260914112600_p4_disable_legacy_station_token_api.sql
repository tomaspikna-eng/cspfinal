-- P4 cleanup: the legacy stations.token tournament API has no callers in the
-- current CSP frontend and duplicates the canonical tournament_resources/device_token flow.
-- Keep the functions for service-role compatibility/rollback, but remove browser access.

revoke execute on function public.get_station_by_token(text) from public, anon, authenticated;
revoke execute on function public.get_station_live_match(text) from public, anon, authenticated;
revoke execute on function public.station_complete_match(text,integer,integer) from public, anon, authenticated;
revoke execute on function public.station_pause_match_clock(text) from public, anon, authenticated;
revoke execute on function public.station_update_match_score(text,integer,integer) from public, anon, authenticated;

grant execute on function public.get_station_by_token(text) to service_role;
grant execute on function public.get_station_live_match(text) to service_role;
grant execute on function public.station_complete_match(text,integer,integer) to service_role;
grant execute on function public.station_pause_match_clock(text) to service_role;
grant execute on function public.station_update_match_score(text,integer,integer) to service_role;
