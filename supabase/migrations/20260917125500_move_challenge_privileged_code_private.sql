-- Keep privileged challenge writes outside the exposed public API schema.
-- Public RPCs remain SECURITY INVOKER wrappers with explicit ACLs.

create schema if not exists challenge_private;
revoke all on schema challenge_private from public, anon;
grant usage on schema challenge_private to authenticated, service_role;

alter function public.refresh_my_challenge_progress() set schema challenge_private;
alter function challenge_private.refresh_my_challenge_progress()
  rename to refresh_my_challenge_progress_core;

alter function public.join_my_challenge(uuid) set schema challenge_private;
alter function challenge_private.join_my_challenge(uuid)
  rename to join_my_challenge_core;

revoke all on function challenge_private.refresh_my_challenge_progress_core() from public, anon;
revoke all on function challenge_private.join_my_challenge_core(uuid) from public, anon;
grant execute on function challenge_private.refresh_my_challenge_progress_core() to authenticated, service_role;
grant execute on function challenge_private.join_my_challenge_core(uuid) to authenticated, service_role;

create function public.refresh_my_challenge_progress()
returns void
language sql
security invoker
set search_path = ''
as $$
  select challenge_private.refresh_my_challenge_progress_core();
$$;

create function public.join_my_challenge(p_challenge_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select challenge_private.join_my_challenge_core(p_challenge_id);
$$;

comment on function public.refresh_my_challenge_progress() is
  'Invoker wrapper for server-calculated challenge progress of the authenticated PRO+ player.';
comment on function public.join_my_challenge(uuid) is
  'Invoker wrapper for the authenticated PRO+ player manual challenge join.';

revoke all on function public.refresh_my_challenge_progress() from public, anon;
revoke all on function public.join_my_challenge(uuid) from public, anon;
grant execute on function public.refresh_my_challenge_progress() to authenticated, service_role;
grant execute on function public.join_my_challenge(uuid) to authenticated, service_role;

