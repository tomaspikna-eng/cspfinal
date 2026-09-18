-- Restore browser challenge write privileges required by secured owner-only RLS.
grant select, insert, update on table public.player_challenges to authenticated;
grant select, insert, update on table public.player_challenges to service_role;
