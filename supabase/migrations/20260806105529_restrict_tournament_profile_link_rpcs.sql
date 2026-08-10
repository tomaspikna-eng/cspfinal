revoke execute on function public.export_event_to_tournament(uuid,text,integer,integer) from public, anon;
grant execute on function public.export_event_to_tournament(uuid,text,integer,integer) to authenticated, service_role;

revoke execute on function public.sync_draft_tournament_players(uuid,jsonb) from public, anon;
grant execute on function public.sync_draft_tournament_players(uuid,jsonb) to authenticated, service_role;
