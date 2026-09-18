-- Connect Sports Pro — public player search
-- Exposes only fields needed to find and open a public player profile.

create or replace function public.search_public_players(
  p_query text,
  p_limit integer default 20
)
returns table (
  id uuid,
  full_name text,
  role text,
  plan text,
  avatar_url text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    p.id,
    p.full_name,
    p.role::text,
    public.current_plan(p.id)::text,
    p.avatar_url
  from public.profiles p
  where p.role::text = 'player'
    and length(btrim(coalesce(p_query,''))) >= 2
    and p.full_name ilike '%' || replace(replace(btrim(p_query), '%', ''), '_', '') || '%'
  order by p.full_name asc
  limit least(greatest(coalesce(p_limit,20),1),20);
$$;

comment on function public.search_public_players(text,integer) is
  'Safe public player search. Returns only public routing fields and never exposes email, billing or admin data.';

revoke all on function public.search_public_players(text,integer) from public;
grant execute on function public.search_public_players(text,integer) to anon, authenticated, service_role;
