create index if not exists tournament_display_screens_created_by_idx on public.tournament_display_screens(created_by) where created_by is not null;
create index if not exists display_pairing_requests_screen_idx on public.display_pairing_requests(screen_id) where screen_id is not null;

