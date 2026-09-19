create or replace function public.get_station_live_timer(p_station_id uuid)
returns table(
  station_id uuid,
  station_status text,
  session_status text,
  started_at timestamptz,
  accumulated_seconds integer
)
language sql
security definer
stable
set search_path=public,pg_temp
as $$
  select
    s.id,
    s.status,
    ls.status,
    ls.started_at,
    coalesce(ls.accumulated_seconds,0)
  from public.stations s
  left join lateral (
    select x.status,x.started_at,x.accumulated_seconds
    from public.club_manager_live_sessions x
    where x.station_id=s.id and x.status in ('running','paused')
    order by x.created_at desc
    limit 1
  ) ls on true
  where s.id=p_station_id
  limit 1;
$$;

grant execute on function public.get_station_live_timer(uuid) to anon, authenticated;
