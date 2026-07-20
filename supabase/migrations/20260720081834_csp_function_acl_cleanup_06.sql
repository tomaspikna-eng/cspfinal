-- Remove implicit PUBLIC execute grants and explicitly grant intended callers.
revoke execute on function public.can_access_magazine_cms(uuid) from public,anon;
revoke execute on function public.can_create_tournament(uuid) from public,anon;
revoke execute on function public.current_plan(uuid) from public,anon;
revoke execute on function public.has_feature_access(uuid,text) from public,anon;
revoke execute on function public.has_plan_at_least(uuid,text) from public,anon;
revoke execute on function public.is_admin(uuid) from public,anon;
revoke execute on function public.remaining_tournament_quota(uuid) from public,anon;
grant execute on function public.can_access_magazine_cms(uuid),public.can_create_tournament(uuid),public.current_plan(uuid),public.has_feature_access(uuid,text),public.has_plan_at_least(uuid,text),public.is_admin(uuid),public.remaining_tournament_quota(uuid) to authenticated,service_role;
revoke execute on function public.get_station_by_token(text) from public;
grant execute on function public.get_station_by_token(text) to anon,authenticated,service_role;

revoke execute on function public.start_training_session(uuid),public.pause_training_session(uuid),public.complete_training_session(uuid,jsonb,text),public.call_match(uuid),public.get_match_arrival_status(uuid),public.set_match_ready(uuid),public.forfeit_match(uuid,uuid,text),public.complete_tournament(uuid,jsonb),public.archive_tournament(uuid),public.complete_round_robin_phase(uuid,jsonb,text),public.start_shot_clock(uuid,uuid,boolean),public.pause_shot_clock(uuid),public.use_shot_clock_extension(uuid,uuid) from public,anon;
grant execute on function public.start_training_session(uuid),public.pause_training_session(uuid),public.complete_training_session(uuid,jsonb,text),public.call_match(uuid),public.get_match_arrival_status(uuid),public.set_match_ready(uuid),public.forfeit_match(uuid,uuid,text),public.complete_tournament(uuid,jsonb),public.archive_tournament(uuid),public.complete_round_robin_phase(uuid,jsonb,text),public.start_shot_clock(uuid,uuid,boolean),public.pause_shot_clock(uuid),public.use_shot_clock_extension(uuid,uuid) to authenticated,service_role;
