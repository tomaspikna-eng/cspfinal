-- Challenge progress and completion are server-calculated. Players may read
-- their rows, but cannot directly insert or update progress through Data API.

revoke insert, update, delete on table public.player_challenges from authenticated;
grant select on table public.player_challenges to authenticated;

drop policy if exists player_challenges_owner_insert on public.player_challenges;
drop policy if exists player_challenges_owner_update on public.player_challenges;

alter function public.refresh_my_challenge_progress() security definer;
alter function public.join_my_challenge(uuid) security definer;

comment on function public.refresh_my_challenge_progress() is
  'Server-calculates only the authenticated PRO+ player progress from verified CSP activity.';
comment on function public.join_my_challenge(uuid) is
  'Server-controlled manual challenge join for the authenticated PRO+ player.';

revoke all on function public.refresh_my_challenge_progress() from public, anon;
revoke all on function public.join_my_challenge(uuid) from public, anon;
grant execute on function public.refresh_my_challenge_progress() to authenticated, service_role;
grant execute on function public.join_my_challenge(uuid) to authenticated, service_role;

