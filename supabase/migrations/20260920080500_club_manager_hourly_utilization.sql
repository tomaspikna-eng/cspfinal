create or replace function public.get_club_manager_reports(
  p_club_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_from is null or p_to is null or p_from >= p_to then raise exception 'INVALID_RANGE'; end if;

  if not exists (
    select 1 from public.clubs c
    where c.id=p_club_id
      and (c.owner_id=v_uid or public.is_admin(v_uid))
  ) then
    raise exception 'CLUB_ACCESS_DENIED';
  end if;

  with station_capacity as (
    select count(*)::numeric as active_stations
    from public.stations st
    where st.club_id=p_club_id and st.is_active
  ),
  sessions as (
    select
      ls.*,
      coalesce(ls.final_amount,ls.total_amount,0)::numeric as amount,
      coalesce(ls.adjustment_amount,0)::numeric as adjustment,
      coalesce(ls.accumulated_seconds,0)::bigint as seconds,
      coalesce(ls.settled_at,ls.stopped_at,ls.started_at,ls.created_at) as event_at,
      ls.started_at as session_start,
      coalesce(ls.stopped_at,ls.settled_at,ls.updated_at,now()) as session_end
    from public.club_manager_live_sessions ls
    where ls.club_id=p_club_id
      and ls.started_at is not null
      and coalesce(ls.stopped_at,ls.settled_at,ls.updated_at,now()) > p_from
      and ls.started_at < p_to
      and ls.status in ('running','paused','stopped','settled')
  ),
  paid as (
    select * from sessions where payment_status='paid' or status='settled'
  ),
  res as (
    select *
    from public.reservations r
    where r.club_id=p_club_id
      and r.starts_at >= p_from and r.starts_at < p_to
  ),
  station_use as (
    select
      s.station_id,
      coalesce(nullif(s.station_name_snapshot,''),st.name,'Stanica') as station_name,
      coalesce(nullif(s.station_sport_snapshot,''),st.sport,'') as sport,
      count(*) filter (where s.event_at >= p_from and s.event_at < p_to)::int as sessions,
      coalesce(sum(
        greatest(
          extract(epoch from (
            least(s.session_end,p_to) - greatest(s.session_start,p_from)
          )),
          0
        )
      ),0)::bigint as seconds,
      coalesce(sum(case when (s.payment_status='paid' or s.status='settled') and s.event_at >= p_from and s.event_at < p_to then s.amount else 0 end),0)::numeric as revenue,
      coalesce(avg(nullif(s.seconds,0)) filter (where s.event_at >= p_from and s.event_at < p_to),0)::numeric as avg_seconds
    from sessions s
    left join public.stations st on st.id=s.station_id
    group by s.station_id,coalesce(nullif(s.station_name_snapshot,''),st.name,'Stanica'),coalesce(nullif(s.station_sport_snapshot,''),st.sport,'')
  ),
  daily as (
    select
      d::date as day,
      coalesce(count(s.id) filter (where s.event_at >= d and s.event_at < d + interval '1 day'),0)::int as sessions,
      coalesce(sum(case when (s.payment_status='paid' or s.status='settled') and s.event_at >= d and s.event_at < d + interval '1 day' then s.amount else 0 end),0)::numeric as revenue,
      coalesce(sum(
        greatest(
          extract(epoch from (
            least(s.session_end,d + interval '1 day') - greatest(s.session_start,d)
          )),
          0
        )
      ),0)::bigint as seconds
    from generate_series(date_trunc('day',p_from), date_trunc('day',p_to - interval '1 second'), interval '1 day') d
    left join sessions s on s.session_start < d + interval '1 day' and s.session_end > d
    group by d
    order by d
  ),
  hour_slots as (
    select generate_series(date_trunc('hour',p_from), date_trunc('hour',p_to - interval '1 second'), interval '1 hour') as slot_start
  ),
  hourly_raw as (
    select
      extract(hour from h.slot_start)::int as hour_of_day,
      h.slot_start::date as slot_day,
      coalesce(sum(
        greatest(
          extract(epoch from (
            least(s.session_end,h.slot_start + interval '1 hour') - greatest(s.session_start,h.slot_start)
          )),
          0
        )
      ),0)::numeric as occupied_seconds
    from hour_slots h
    left join sessions s
      on s.session_start < h.slot_start + interval '1 hour'
     and s.session_end > h.slot_start
    group by h.slot_start
  ),
  hourly_utilization as (
    select
      hr.hour_of_day,
      count(*)::int as sampled_days,
      coalesce(sum(hr.occupied_seconds),0)::numeric as occupied_seconds,
      coalesce(sc.active_stations,0)::numeric as active_stations,
      case
        when coalesce(sc.active_stations,0) <= 0 then 0
        else round(
          least(
            100::numeric,
            greatest(
              0::numeric,
              (coalesce(sum(hr.occupied_seconds),0) /
               (count(*)::numeric * sc.active_stations * 3600::numeric)) * 100
            )
          ),
          1
        )
      end as utilization_percent
    from hourly_raw hr
    cross join station_capacity sc
    group by hr.hour_of_day,sc.active_stations
    order by hr.hour_of_day
  ),
  payments as (
    select coalesce(nullif(payment_method,''),'other') as method,count(*)::int as count,coalesce(sum(amount),0)::numeric as amount
    from paid
    where event_at >= p_from and event_at < p_to
    group by 1
  ),
  customers as (
    select coalesce(nullif(customer_type,''),'walkin') as customer_type,count(*)::int as count,coalesce(sum(amount),0)::numeric as amount
    from paid
    where event_at >= p_from and event_at < p_to
    group by 1
  ),
  reservation_status as (
    select status,count(*)::int as count from res group by status
  ),
  completed_period_sessions as (
    select * from sessions where event_at >= p_from and event_at < p_to and status in ('stopped','settled')
  )
  select jsonb_build_object(
    'period',jsonb_build_object('from',p_from,'to',p_to),
    'summary',jsonb_build_object(
      'revenue',coalesce((select sum(amount) from paid where event_at >= p_from and event_at < p_to),0),
      'sessions',coalesce((select count(*) from completed_period_sessions),0),
      'paid_sessions',coalesce((select count(*) from paid where event_at >= p_from and event_at < p_to),0),
      'play_seconds',coalesce((select sum(seconds) from completed_period_sessions),0),
      'avg_session_seconds',coalesce((select round(avg(seconds))::bigint from completed_period_sessions),0),
      'adjustments_total',coalesce((select sum(adjustment) from completed_period_sessions),0),
      'reservations',coalesce((select count(*) from res where status in ('pending','confirmed','checked_in','completed')),0),
      'cancelled_reservations',coalesce((select count(*) from res where status='cancelled'),0),
      'active_stations',coalesce((select active_stations from station_capacity),0)
    ),
    'hourly_utilization',coalesce((select jsonb_agg(to_jsonb(x) order by x.hour_of_day) from hourly_utilization x),'[]'::jsonb),
    'daily',coalesce((select jsonb_agg(to_jsonb(d) order by d.day) from daily d),'[]'::jsonb),
    'stations',coalesce((select jsonb_agg(to_jsonb(x) order by x.seconds desc,x.revenue desc) from station_use x),'[]'::jsonb),
    'payments',coalesce((select jsonb_agg(to_jsonb(x) order by x.amount desc) from payments x),'[]'::jsonb),
    'customers',coalesce((select jsonb_agg(to_jsonb(x) order by x.amount desc) from customers x),'[]'::jsonb),
    'reservation_status',coalesce((select jsonb_agg(to_jsonb(x) order by x.status) from reservation_status x),'[]'::jsonb)
  ) into v_result;

  return coalesce(v_result,'{}'::jsonb);
end $$;

grant execute on function public.get_club_manager_reports(uuid,timestamptz,timestamptz) to authenticated;