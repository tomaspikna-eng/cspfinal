alter function public.touch_reservation_updated_at() set search_path = public;
revoke all on function public.can_manage_club(uuid) from public, anon;
grant execute on function public.can_manage_club(uuid) to authenticated;
revoke all on function public.validate_reservation_relations() from public, anon, authenticated;
revoke all on function public.validate_block_conflicts() from public, anon, authenticated;
revoke all on function public.touch_reservation_updated_at() from public, anon, authenticated;
revoke all on table public.reservation_settings from anon;
revoke all on table public.reservation_opening_hours from anon;
revoke all on table public.reservations from anon;
revoke all on table public.reservation_blocks from anon;

