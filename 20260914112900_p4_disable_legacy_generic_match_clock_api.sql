-- P4 cleanup: generic manual match-clock RPCs are not used by the current frontend.
-- Canonical tournament lifecycle auto-starts when both players are present.
-- emergency_start_tournament_match(uuid) remains the explicit owner/admin escape hatch.

revoke execute on function public.start_match_clock(uuid) from public, anon, authenticated;
revoke execute on function public.pause_match_clock(uuid) from public, anon, authenticated;
revoke execute on function public.stop_match_clock(uuid) from public, anon, authenticated;

grant execute on function public.start_match_clock(uuid) to service_role;
grant execute on function public.pause_match_clock(uuid) to service_role;
grant execute on function public.stop_match_clock(uuid) to service_role;
