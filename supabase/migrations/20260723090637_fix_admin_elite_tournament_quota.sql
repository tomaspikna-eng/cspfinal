create or replace function public.remaining_tournament_quota(uid uuid)
returns integer
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  effective_plan text;
  used_count integer;
begin
  -- Admin is always unlimited regardless of subscription/plan mapping.
  if public.is_admin(uid) then
    return null;
  end if;

  effective_plan := public.current_plan(uid);

  -- Top tiers are unlimited.
  if effective_plan in ('ultra', 'elite') then
    return null;
  end if;

  if effective_plan = 'free' then
    return 0;
  end if;

  -- Pro tier: 10 created tournaments.
  select coalesce(tournaments_created_count, 0)
    into used_count
  from public.profiles
  where id = uid;

  return greatest(10 - coalesce(used_count, 0), 0);
end;
$function$;

