create or replace function public.get_club_manager_dashboard_stats(
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
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;

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
      coalesce(ls.accumulated_seconds,0)::bigint as seconds
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
      and r.starts_at >= p_from
      and r.starts_at < p_to
  ),
  station_use as (
    select
      s.station_id,
      coalesce(nullif(s.station_name_snapshot,''),st.name,'Stanica') as station_name,
      coalesce(nullif(s.station_sport_snapshot,''),st.sport,'') as sport,
      count(*)::int as sessions,
      coalesce(sum(s.seconds),0)::bigint as seconds,
      coalesce(sum(case when s.payment_status='paid' or s.status='settled' then s.amount else 0 end),0)::numeric as revenue
    from sessions s
    left join public.stations st on st.id=s.station_id
    group by s.station_id,coalesce(nullif(s.station_name_snapshot,''),st.name,'Stanica'),coalesce(nullif(s.station_sport_snapshot,''),st.sport,'')
  ),
  payment_breakdown as (
    select coalesce(nullif(payment_method,''),'other') as method,count(*)::int as count,coalesce(sum(amount),0)::numeric as amount
    from paid
    group by 1
  ),
  customer_breakdown as (
    select coalesce(nullif(customer_type,''),'walkin') as customer_type,count(*)::int as count,coalesce(sum(amount),0)::numeric as amount
    from paid
    group by 1
  )
  select jsonb_build_object(
    'period',jsonb_build_object('from',p_from,'to',p_to),
    'summary',jsonb_build_object(
      'revenue',coalesce((select sum(amount) from paid),0),
      'sessions',coalesce((select count(*) from sessions),0),
      'paid_sessions',coalesce((select count(*) from paid),0),
      'play_seconds',coalesce((select sum(seconds) from sessions),0),
      'avg_session_seconds',coalesce((select round(avg(seconds))::bigint from sessions),0),
      'reservations',coalesce((select count(*) from res where status in ('pending','confirmed','checked_in','completed')),0),
      'cancelled_reservations',coalesce((select count(*) from res where status='cancelled'),0),
      'active_stations',coalesce((select count(*) from public.stations st where st.club_id=p_club_id and st.is_active),0)
    ),
    'top_stations',coalesce((
      select jsonb_agg(to_jsonb(x) order by x.seconds desc,x.revenue desc)
      from (
        select station_id,station_name,sport,sessions,seconds,revenue
        from station_use
        order by seconds desc,revenue desc
        limit 8
      ) x
    ),'[]'::jsonb),
    'payments',coalesce((select jsonb_agg(to_jsonb(p) order by p.amount desc) from payment_breakdown p),'[]'::jsonb),
    'customers',coalesce((select jsonb_agg(to_jsonb(c) order by c.amount desc) from customer_breakdown c),'[]'::jsonb)
  ) into v_result;

  return coalesce(v_result,'{}'::jsonb);
end $$;

grant execute on function public.get_club_manager_dashboard_stats(uuid,timestamptz,timestamptz) to authenticated;
