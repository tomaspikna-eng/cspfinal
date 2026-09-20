create or replace function public.get_public_club_reservations(
  p_owner_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
returns table (
  starts_at timestamptz,
  ends_at timestamptz,
  station_name text,
  status text
)
language sql
stable
security definer
set search_path = ''
as $$
  select r.starts_at,r.ends_at,r.station_name_snapshot,r.status
  from public.reservations r
  join public.clubs c on c.id=r.club_id
  join public.profiles p on p.id=c.owner_id
  where c.owner_id=p_owner_id
    and p.role::text in ('club','organization')
    and r.starts_at>=p_from
    and r.starts_at<p_to
    and r.status<>'cancelled'
  order by r.starts_at;
$$;

revoke all on function public.get_public_club_reservations(uuid,timestamptz,timestamptz) from public;
grant execute on function public.get_public_club_reservations(uuid,timestamptz,timestamptz) to anon, authenticated, service_role;