revoke all on function public.complete_organizer_match(uuid,integer,integer,uuid) from public, anon;
grant execute on function public.complete_organizer_match(uuid,integer,integer,uuid) to authenticated, service_role;
