create or replace function public.get_public_event_author_name(p_event_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select p.full_name
  from public.events e
  join public.profiles p on p.id = e.owner_id
  where e.id = p_event_id
    and coalesce(e.visibility, 'public') = 'public'
  limit 1;
$$;

grant execute on function public.get_public_event_author_name(uuid) to anon, authenticated;

