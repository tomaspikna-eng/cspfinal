
create or replace function public.get_public_event_calendar(p_limit integer default 12)
returns table(
  id uuid,club_name text,event_type text,title text,sport text,discipline text,
  starts_at timestamptz,ends_at timestamptz,city text,location_text text,cover_image_url text
)
language sql
stable
security definer
set search_path to 'public'
as $function$
  with upcoming as (
    select
      e.*,
      row_number() over (
        partition by coalesce(e.series_id,e.id)
        order by e.starts_at,e.series_round_number nulls first
      ) as series_position
    from public.events e
    where e.status='published'
      and e.visibility='public'
      and e.starts_at>=now()
  )
  select
    e.id,
    coalesce(c.name,p.full_name,'Connect Sports Pro') as club_name,
    case
      when e.series_id is not null then e.event_type||' · '||e.series_round_number::text||'. kolo'
      else e.event_type
    end as event_type,
    e.title,e.sport,e.discipline,e.starts_at,e.ends_at,e.city,e.location_text,e.cover_image_url
  from upcoming e
  left join public.clubs c on c.id=e.club_id
  left join public.profiles p on p.id=e.owner_id
  where e.series_position=1
  order by e.starts_at asc
  limit greatest(1,least(coalesce(p_limit,12),50));
$function$;

