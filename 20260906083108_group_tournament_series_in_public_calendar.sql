
create or replace function public.get_grouped_tournament_calendar()
returns table (
  group_id uuid,
  series_id uuid,
  is_series boolean,
  name text,
  sport text,
  discipline text,
  venue text,
  city text,
  country text,
  organizer_name text,
  first_event_date date,
  last_event_date date,
  round_count integer,
  rounds jsonb
)
language sql
stable
security invoker
set search_path = ''
as $function$
  with visible as (
    select
      tc.*,
      e.series_id,
      e.series_round_number,
      es.title as series_title
    from public.tournament_calendar tc
    left join public.events e on e.id = tc.event_id
    left join public.event_series es on es.id = e.series_id
    where tc.visibility = 'public'
      and tc.status not in ('draft','archived','cancelled')
  )
  select
    coalesce(v.series_id,v.id) as group_id,
    v.series_id,
    (v.series_id is not null) as is_series,
    coalesce(
      max(v.series_title),
      (array_agg(v.name order by v.event_date,v.id))[1]
    ) as name,
    (array_agg(v.sport order by v.event_date,v.id))[1] as sport,
    (array_agg(v.discipline order by v.event_date,v.id))[1] as discipline,
    (array_agg(v.venue order by v.event_date,v.id))[1] as venue,
    (array_agg(v.city order by v.event_date,v.id))[1] as city,
    (array_agg(v.country order by v.event_date,v.id))[1] as country,
    (array_agg(v.organizer_name order by v.event_date,v.id))[1] as organizer_name,
    min(v.event_date) as first_event_date,
    max(v.event_date) as last_event_date,
    count(*)::integer as round_count,
    jsonb_agg(
      jsonb_build_object(
        'id',v.id,
        'event_id',v.event_id,
        'tournament_id',v.tournament_id,
        'name',v.name,
        'event_date',v.event_date,
        'starts_at',v.starts_at,
        'series_round_number',v.series_round_number,
        'registration_enabled',v.registration_enabled,
        'registration_deadline',v.registration_deadline,
        'external_url',v.external_url,
        'public_slug',v.public_slug,
        'status',v.status
      )
      order by v.event_date,v.id
    ) as rounds
  from visible v
  group by coalesce(v.series_id,v.id),v.series_id
  order by min(v.event_date),name;
$function$;

revoke all on function public.get_grouped_tournament_calendar() from public;
grant execute on function public.get_grouped_tournament_calendar() to anon, authenticated, service_role;

