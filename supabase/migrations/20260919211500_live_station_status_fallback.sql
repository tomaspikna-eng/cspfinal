create or replace function public.get_club_live_station_view(p_club_id uuid)
returns table(
  station_id uuid,
  station_name text,
  sport text,
  station_status text,
  is_active boolean,
  live_state text,
  live_source text,
  live_started_at timestamptz,
  live_label text,
  reservation_id uuid,
  reservation_starts_at timestamptz,
  reservation_ends_at timestamptz
)
language plpgsql
security definer
stable
set search_path=public,pg_temp
as $$
begin
  if auth.uid() is null then raise exception 'AUTHENTICATION_REQUIRED'; end if;
  if not exists (
    select 1 from public.clubs c
    where c.id=p_club_id
      and (c.owner_id=auth.uid() or public.is_admin(auth.uid()))
  ) then raise exception 'CLUB_ACCESS_DENIED'; end if;

  return query
  select
    s.id,
    s.name,
    s.sport,
    s.status,
    s.is_active,
    case
      when not s.is_active or s.status in ('service','blocked') then 'maintenance'
      when lm.id is not null or lt.id is not null or s.status in ('running','tournament') then 'occupied'
      when rr.id is not null then 'reserved'
      else 'free'
    end as live_state,
    case
      when lm.id is not null then 'match'
      when lt.id is not null then 'training'
      when s.status in ('running','tournament') then 'station'
      when rr.id is not null then 'reservation'
      else null
    end as live_source,
    coalesce(lm.started_at,lt.started_at,rr.starts_at) as live_started_at,
    case
      when lm.id is not null then coalesce(nullif(lm.station_label,''),'Turnajový zápas')
      when lt.id is not null then coalesce(array_to_string(lt.player_names,' vs '),'Tréning')
      when s.status in ('running','tournament') then 'Aktívna hra'
      when rr.id is not null then coalesce(rr.customer_name,'Rezervácia')
      else null
    end as live_label,
    rr.id,
    rr.starts_at,
    rr.ends_at
  from public.stations s
  left join lateral (
    select m.id,m.started_at,m.station_label
    from public.matches m
    where m.station_id=s.id
      and m.status in ('in_progress','live')
      and m.completed_at is null
    order by coalesce(m.started_at,m.updated_at) desc
    limit 1
  ) lm on true
  left join lateral (
    select ts.id,ts.started_at,ts.player_names
    from public.training_sessions ts
    where ts.station_id=s.id
      and ts.status in ('active','paused')
    order by coalesce(ts.started_at,ts.updated_at) desc
    limit 1
  ) lt on lm.id is null
  left join lateral (
    select r.id,r.starts_at,r.ends_at,r.customer_name
    from public.reservations r
    where r.station_id=s.id
      and r.status in ('pending','confirmed','checked_in')
      and now() >= r.starts_at and now() < r.ends_at
    order by r.starts_at desc
    limit 1
  ) rr on lm.id is null and lt.id is null and s.status not in ('running','tournament')
  where s.club_id=p_club_id
  order by s.sort_order nulls last,s.name;
end;
$$;

grant execute on function public.get_club_live_station_view(uuid) to authenticated;