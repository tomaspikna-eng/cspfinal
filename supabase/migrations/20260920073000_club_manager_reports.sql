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

  with sessions as (
    select
      ls.*,
      coalesce(ls.final_amount,ls.total_amount,0)::numeric as amount,
      coalesce(ls.adjustment_amount,0)::numeric as adjustment,
      coalesce(ls.accumulated_seconds,0)::bigint as seconds,
      coalesce(ls.settled_at,ls.stopped_at,ls.started_at,ls.created_at) as event_at
    from public.club_manager_live_sessions ls
    where ls.club_id=p_club_id
      and coalesce(ls.settled_at,ls.stopped_at,ls.started_at,ls.created_at) >= p_from
      and coalesce(ls.settled_at,ls.stopped_at,ls.started_at,ls.created_at) < p_to
      and ls.status in ('stopped','settled')
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
      count(*)::int as sessions,
      coalesce(sum(s.seconds),0)::bigint as seconds,
      coalesce(sum(case when s.payment_status='paid' or s.status='settled' then s.amount else 0 end),0)::numeric as revenue,
      coalesce(avg(nullif(s.seconds,0)),0)::numeric as avg_seconds
    from sessions s
    left join public.stations st on st.id=s.station_id
    group by s.station_id,coalesce(nullif(s.station_name_snapshot,''),st.name,'Stanica'),coalesce(nullif(s.station_sport_snapshot,''),st.sport,'')
  ),
  daily as (
    select
      d::date as day,
      coalesce(count(s.id),0)::int as sessions,
      coalesce(sum(case when s.payment_status='paid' or s.status='settled' then s.amount else 0 end),0)::numeric as revenue,
      coalesce(sum(s.seconds),0)::bigint as seconds
    from generate_series(date_trunc('day',p_from), date_trunc('day',p_to - interval '1 second'), interval '1 day') d
    left join sessions s on date_trunc('day',s.event_at)=d
    group by d
    order by d
  ),
  payments as (
    select coalesce(nullif(payment_method,''),'other') as method,count(*)::int as count,coalesce(sum(amount),0)::numeric as amount
    from paid group by 1
  ),
  customers as (
    select coalesce(nullif(customer_type,''),'walkin') as customer_type,count(*)::int as count,coalesce(sum(amount),0)::numeric as amount
    from paid group by 1
  ),
  reservation_status as (
    select status,count(*)::int as count from res group by status
  )
  select jsonb_build_object(
    'period',jsonb_build_object('from',p_from,'to',p_to),
    'summary',jsonb_build_object(
      'revenue',coalesce((select sum(amount) from paid),0),
      'sessions',coalesce((select count(*) from sessions),0),
      'paid_sessions',coalesce((select count(*) from paid),0),
      'play_seconds',coalesce((select sum(seconds) from sessions),0),
      'avg_session_seconds',coalesce((select round(avg(seconds))::bigint from sessions),0),
      'adjustments_total',coalesce((select sum(adjustment) from sessions),0),
      'reservations',coalesce((select count(*) from res where status in ('pending','confirmed','checked_in','completed')),0),
      'cancelled_reservations',coalesce((select count(*) from res where status='cancelled'),0),
      'active_stations',coalesce((select count(*) from public.stations st where st.club_id=p_club_id and st.is_active),0)
    ),
    'daily',coalesce((select jsonb_agg(to_jsonb(d) order by d.day) from daily d),'[]'::jsonb),
    'stations',coalesce((select jsonb_agg(to_jsonb(x) order by x.seconds desc,x.revenue desc) from station_use x),'[]'::jsonb),
    'payments',coalesce((select jsonb_agg(to_jsonb(x) order by x.amount desc) from payments x),'[]'::jsonb),
    'customers',coalesce((select jsonb_agg(to_jsonb(x) order by x.amount desc) from customers x),'[]'::jsonb),
    'reservation_status',coalesce((select jsonb_agg(to_jsonb(x) order by x.status) from reservation_status x),'[]'::jsonb)
  ) into v_result;

  return coalesce(v_result,'{}'::jsonb);
end $$;

grant execute on function public.get_club_manager_reports(uuid,timestamptz,timestamptz) to authenticated;