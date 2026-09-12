alter table public.tournaments add column if not exists source_event_id uuid references public.events(id) on delete set null;
create unique index if not exists tournaments_source_event_id_key on public.tournaments(source_event_id) where source_event_id is not null;

create or replace function public.export_event_to_tournament(
  p_event_id uuid,
  p_format text default 'sko',
  p_groups_count integer default null,
  p_advance_count integer default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_event public.events;
  v_tournament public.tournaments;
  v_player_count integer := 0;
  v_player_name text;
begin
  select * into v_event
  from public.events
  where id=p_event_id
    and (owner_id=auth.uid() or public.is_admin(auth.uid()))
  for update;

  if v_event.id is null then
    raise exception 'EVENT_NOT_FOUND_OR_ACCESS_DENIED';
  end if;

  if coalesce(v_event.sport,'')='' or coalesce(v_event.discipline,'')='' then
    raise exception 'EVENT_SPORT_AND_DISCIPLINE_REQUIRED';
  end if;

  if p_format not in ('rr','sko','dko','rr_sko','rr_dko','karty') then
    raise exception 'INVALID_TOURNAMENT_FORMAT';
  end if;

  select * into v_tournament
  from public.tournaments
  where source_event_id=v_event.id
  for update;

  if v_tournament.id is null then
    insert into public.tournaments(
      owner_id,name,sport,discipline,format,date,venue,groups_count,advance_count,
      status,config,city,visibility,registration_enabled,registration_deadline,
      max_participants,source_event_id
    ) values (
      v_event.owner_id,
      v_event.title,
      v_event.sport,
      v_event.discipline,
      p_format,
      (v_event.starts_at at time zone 'Europe/Bratislava')::date,
      v_event.location_text,
      p_groups_count,
      p_advance_count,
      'draft',
      jsonb_build_object(
        'source_event_id',v_event.id,
        'source_event_description',v_event.description,
        'source_event_starts_at',v_event.starts_at,
        'source_event_ends_at',v_event.ends_at,
        'source_event_type',v_event.event_type,
        'source_event_cover_image_url',v_event.cover_image_url
      ),
      v_event.city,
      v_event.visibility,
      v_event.registration_enabled,
      v_event.registration_deadline,
      v_event.max_participants,
      v_event.id
    ) returning * into v_tournament;
  else
    update public.tournaments
    set name=v_event.title,
        sport=v_event.sport,
        discipline=v_event.discipline,
        format=coalesce(p_format,format),
        date=(v_event.starts_at at time zone 'Europe/Bratislava')::date,
        venue=v_event.location_text,
        groups_count=coalesce(p_groups_count,groups_count),
        advance_count=coalesce(p_advance_count,advance_count),
        city=v_event.city,
        visibility=v_event.visibility,
        registration_enabled=v_event.registration_enabled,
        registration_deadline=v_event.registration_deadline,
        max_participants=v_event.max_participants,
        config=coalesce(config,'{}'::jsonb) || jsonb_build_object(
          'source_event_id',v_event.id,
          'source_event_description',v_event.description,
          'source_event_starts_at',v_event.starts_at,
          'source_event_ends_at',v_event.ends_at,
          'source_event_type',v_event.event_type,
          'source_event_cover_image_url',v_event.cover_image_url
        ),
        updated_at=now()
    where id=v_tournament.id
    returning * into v_tournament;
  end if;

  for v_player_name in
    select distinct trim(coalesce(nullif(full_name,''),nickname))
    from public.event_preregistrations
    where event_id=v_event.id
      and trim(coalesce(nullif(full_name,''),nickname))<>''
    order by 1
  loop
    insert into public.tournament_players(tournament_id,name)
    select v_tournament.id,v_player_name
    where not exists (
      select 1 from public.tournament_players tp
      where tp.tournament_id=v_tournament.id
        and lower(trim(tp.name))=lower(v_player_name)
    );
  end loop;

  select count(*) into v_player_count
  from public.tournament_players
  where tournament_id=v_tournament.id;

  return jsonb_build_object(
    'tournament_id',v_tournament.id,
    'source_event_id',v_event.id,
    'player_count',v_player_count,
    'tournament_status',v_tournament.status
  );
end;
$function$;

grant execute on function public.export_event_to_tournament(uuid,text,integer,integer) to authenticated;

