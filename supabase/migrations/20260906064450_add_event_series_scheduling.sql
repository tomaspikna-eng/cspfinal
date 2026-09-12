
create table if not exists public.event_series (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  club_id uuid references public.clubs(id) on delete set null,
  title text not null,
  event_type text not null default 'Turnaj',
  sport text,
  discipline text,
  total_rounds smallint not null,
  status text not null default 'published',
  visibility text not null default 'public',
  ranking_config jsonb not null default '{"method":"placement_points","best_results_count":null,"points":[]}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint event_series_title_check check (length(btrim(title)) between 1 and 160),
  constraint event_series_total_rounds_check check (total_rounds between 2 and 52),
  constraint event_series_status_check check (status = any(array['draft','published','cancelled','completed'])),
  constraint event_series_visibility_check check (visibility = any(array['public','unlisted','private'])),
  constraint event_series_ranking_config_check check (jsonb_typeof(ranking_config) = 'object')
);

comment on table public.event_series is
  'Parent record for a recurring event or tournament series. Individual rounds remain rows in public.events.';
comment on column public.event_series.ranking_config is
  'Configurable series ranking rules. Empty points array means scoring has not yet been configured.';

alter table public.events
  add column if not exists series_id uuid references public.event_series(id) on delete cascade,
  add column if not exists series_round_number smallint;

alter table public.events
  drop constraint if exists events_series_round_number_check;
alter table public.events
  add constraint events_series_round_number_check
  check (series_round_number is null or series_round_number between 1 and 52);

alter table public.events
  drop constraint if exists events_series_pair_check;
alter table public.events
  add constraint events_series_pair_check
  check (
    (series_id is null and series_round_number is null)
    or
    (series_id is not null and series_round_number is not null)
  );

create unique index if not exists events_series_round_unique
  on public.events(series_id,series_round_number)
  where series_id is not null;

create index if not exists event_series_owner_idx
  on public.event_series(owner_id,updated_at desc);

create index if not exists events_series_schedule_idx
  on public.events(series_id,series_round_number,starts_at)
  where series_id is not null;

alter table public.event_series enable row level security;

drop policy if exists event_series_public_select on public.event_series;
create policy event_series_public_select
  on public.event_series
  for select
  to anon,authenticated
  using (status='published' and visibility='public');

drop policy if exists event_series_owner_all on public.event_series;
create policy event_series_owner_all
  on public.event_series
  for all
  to authenticated
  using (owner_id=(select auth.uid()))
  with check (
    owner_id=(select auth.uid())
    and (
      club_id is null
      or exists (
        select 1
        from public.clubs c
        where c.id=event_series.club_id
          and c.owner_id=(select auth.uid())
      )
    )
  );

grant select on public.event_series to anon,authenticated;
grant insert,update,delete on public.event_series to authenticated;

drop trigger if exists event_series_set_updated_at on public.event_series;
create trigger event_series_set_updated_at
before update on public.event_series
for each row execute function public.set_updated_at();

create or replace function public.create_event_series(
  p_event jsonb,
  p_starts_at timestamptz[]
)
returns jsonb
language plpgsql
security invoker
set search_path=''
as $function$
declare
  v_owner uuid := auth.uid();
  v_series_id uuid;
  v_event_id uuid;
  v_first_event_id uuid;
  v_event_ids jsonb := '[]'::jsonb;
  v_count integer;
  v_i integer;
  v_club_id uuid;
  v_title text;
  v_event_type text;
  v_sport text;
  v_discipline text;
  v_location_text text;
  v_city text;
  v_description text;
  v_visibility text;
  v_status text;
  v_registration_enabled boolean;
  v_registration_deadline timestamptz;
  v_deadline_lead interval;
  v_round_deadline timestamptz;
  v_max_participants integer;
  v_cover_image_url text;
begin
  if v_owner is null then raise exception 'AUTHENTICATION_REQUIRED'; end if;
  if p_event is null or jsonb_typeof(p_event)<>'object' then raise exception 'EVENT_PAYLOAD_MUST_BE_OBJECT'; end if;

  v_count:=coalesce(cardinality(p_starts_at),0);
  if v_count<2 or v_count>52 then raise exception 'SERIES_ROUND_COUNT_MUST_BE_2_TO_52'; end if;
  if exists(select 1 from unnest(p_starts_at) d where d is null) then raise exception 'SERIES_DATE_REQUIRED'; end if;
  if (select count(distinct d) from unnest(p_starts_at) d)<>v_count then raise exception 'SERIES_DATES_MUST_BE_UNIQUE'; end if;
  if exists(
    select 1 from generate_subscripts(p_starts_at,1) s(i)
    where s.i>1 and p_starts_at[s.i]<=p_starts_at[s.i-1]
  ) then raise exception 'SERIES_DATES_MUST_BE_ASCENDING'; end if;

  v_title:=nullif(btrim(p_event->>'title'),'');
  v_event_type:=coalesce(nullif(btrim(p_event->>'event_type'),''),'Udalosť');
  v_sport:=nullif(btrim(p_event->>'sport'),'');
  v_discipline:=nullif(btrim(p_event->>'discipline'),'');
  v_location_text:=nullif(btrim(p_event->>'location_text'),'');
  v_city:=nullif(btrim(p_event->>'city'),'');
  v_description:=nullif(btrim(p_event->>'description'),'');
  v_visibility:=coalesce(nullif(btrim(p_event->>'visibility'),''),'public');
  v_status:=coalesce(nullif(btrim(p_event->>'status'),''),'published');
  v_registration_enabled:=coalesce((p_event->>'registration_enabled')::boolean,false);
  v_registration_deadline:=nullif(p_event->>'registration_deadline','')::timestamptz;
  v_max_participants:=nullif(p_event->>'max_participants','')::integer;
  v_cover_image_url:=nullif(btrim(p_event->>'cover_image_url'),'');
  v_club_id:=nullif(p_event->>'club_id','')::uuid;

  if v_title is null then raise exception 'EVENT_TITLE_REQUIRED'; end if;
  if v_registration_deadline is not null and v_registration_deadline>p_starts_at[1] then
    raise exception 'REGISTRATION_DEADLINE_AFTER_FIRST_ROUND';
  end if;
  if v_registration_deadline is not null then
    v_deadline_lead:=p_starts_at[1]-v_registration_deadline;
  end if;

  insert into public.event_series(
    owner_id,club_id,title,event_type,sport,discipline,total_rounds,status,visibility
  ) values (
    v_owner,v_club_id,v_title,v_event_type,v_sport,v_discipline,v_count,v_status,v_visibility
  )
  returning id into v_series_id;

  for v_i in 1..v_count loop
    v_round_deadline:=case
      when v_deadline_lead is null then null
      else p_starts_at[v_i]-v_deadline_lead
    end;

    insert into public.events(
      owner_id,club_id,title,event_type,sport,discipline,location_text,city,starts_at,
      description,visibility,status,registration_enabled,registration_deadline,
      max_participants,cover_image_url,series_id,series_round_number
    ) values (
      v_owner,v_club_id,v_title,v_event_type,v_sport,v_discipline,v_location_text,v_city,p_starts_at[v_i],
      v_description,v_visibility,v_status,v_registration_enabled,v_round_deadline,
      v_max_participants,v_cover_image_url,v_series_id,v_i
    )
    returning id into v_event_id;

    if v_i=1 then v_first_event_id:=v_event_id; end if;
    v_event_ids:=v_event_ids||jsonb_build_array(v_event_id);
  end loop;

  return jsonb_build_object(
    'series_id',v_series_id,
    'first_event_id',v_first_event_id,
    'round_count',v_count,
    'event_ids',v_event_ids
  );
end;
$function$;

create or replace function public.update_event_series(
  p_series_id uuid,
  p_event jsonb,
  p_starts_at timestamptz[]
)
returns jsonb
language plpgsql
security invoker
set search_path=''
as $function$
declare
  v_owner uuid := auth.uid();
  v_series public.event_series%rowtype;
  v_event_id uuid;
  v_first_event_id uuid;
  v_event_ids jsonb := '[]'::jsonb;
  v_count integer;
  v_i integer;
  v_club_id uuid;
  v_title text;
  v_event_type text;
  v_sport text;
  v_discipline text;
  v_location_text text;
  v_city text;
  v_description text;
  v_visibility text;
  v_status text;
  v_registration_enabled boolean;
  v_registration_deadline timestamptz;
  v_deadline_lead interval;
  v_round_deadline timestamptz;
  v_max_participants integer;
  v_cover_image_url text;
  v_blocked_round smallint;
begin
  if v_owner is null then raise exception 'AUTHENTICATION_REQUIRED'; end if;
  if p_series_id is null then raise exception 'SERIES_ID_REQUIRED'; end if;
  if p_event is null or jsonb_typeof(p_event)<>'object' then raise exception 'EVENT_PAYLOAD_MUST_BE_OBJECT'; end if;

  select s.* into v_series
  from public.event_series s
  where s.id=p_series_id and s.owner_id=v_owner
  for update;
  if v_series.id is null then raise exception 'SERIES_NOT_FOUND_OR_ACCESS_DENIED'; end if;

  v_count:=coalesce(cardinality(p_starts_at),0);
  if v_count<2 or v_count>52 then raise exception 'SERIES_ROUND_COUNT_MUST_BE_2_TO_52'; end if;
  if exists(select 1 from unnest(p_starts_at) d where d is null) then raise exception 'SERIES_DATE_REQUIRED'; end if;
  if (select count(distinct d) from unnest(p_starts_at) d)<>v_count then raise exception 'SERIES_DATES_MUST_BE_UNIQUE'; end if;
  if exists(
    select 1 from generate_subscripts(p_starts_at,1) s(i)
    where s.i>1 and p_starts_at[s.i]<=p_starts_at[s.i-1]
  ) then raise exception 'SERIES_DATES_MUST_BE_ASCENDING'; end if;

  v_title:=nullif(btrim(p_event->>'title'),'');
  v_event_type:=coalesce(nullif(btrim(p_event->>'event_type'),''),'Udalosť');
  v_sport:=nullif(btrim(p_event->>'sport'),'');
  v_discipline:=nullif(btrim(p_event->>'discipline'),'');
  v_location_text:=nullif(btrim(p_event->>'location_text'),'');
  v_city:=nullif(btrim(p_event->>'city'),'');
  v_description:=nullif(btrim(p_event->>'description'),'');
  v_visibility:=coalesce(nullif(btrim(p_event->>'visibility'),''),'public');
  v_status:=coalesce(nullif(btrim(p_event->>'status'),''),'published');
  v_registration_enabled:=coalesce((p_event->>'registration_enabled')::boolean,false);
  v_registration_deadline:=nullif(p_event->>'registration_deadline','')::timestamptz;
  v_max_participants:=nullif(p_event->>'max_participants','')::integer;
  v_cover_image_url:=nullif(btrim(p_event->>'cover_image_url'),'');
  v_club_id:=nullif(p_event->>'club_id','')::uuid;

  if v_title is null then raise exception 'EVENT_TITLE_REQUIRED'; end if;
  if v_registration_deadline is not null and v_registration_deadline>p_starts_at[1] then
    raise exception 'REGISTRATION_DEADLINE_AFTER_FIRST_ROUND';
  end if;
  if v_registration_deadline is not null then
    v_deadline_lead:=p_starts_at[1]-v_registration_deadline;
  end if;

  if v_count<v_series.total_rounds then
    select e.series_round_number into v_blocked_round
    from public.events e
    where e.series_id=p_series_id
      and e.series_round_number>v_count
      and (
        e.status='completed'
        or exists(select 1 from public.event_preregistrations ep where ep.event_id=e.id)
        or exists(select 1 from public.tournaments t where t.source_event_id=e.id)
      )
    order by e.series_round_number
    limit 1;

    if v_blocked_round is not null then
      raise exception 'SERIES_ROUND_%_CANNOT_BE_REMOVED',v_blocked_round;
    end if;

    delete from public.events e
    where e.series_id=p_series_id and e.series_round_number>v_count;
  end if;

  update public.event_series
  set club_id=v_club_id,title=v_title,event_type=v_event_type,sport=v_sport,
      discipline=v_discipline,total_rounds=v_count,status=v_status,visibility=v_visibility
  where id=p_series_id;

  for v_i in 1..v_count loop
    v_round_deadline:=case
      when v_deadline_lead is null then null
      else p_starts_at[v_i]-v_deadline_lead
    end;
    v_event_id:=null;

    select e.id into v_event_id
    from public.events e
    where e.series_id=p_series_id and e.series_round_number=v_i
    for update;

    if v_event_id is null then
      insert into public.events(
        owner_id,club_id,title,event_type,sport,discipline,location_text,city,starts_at,
        description,visibility,status,registration_enabled,registration_deadline,
        max_participants,cover_image_url,series_id,series_round_number
      ) values (
        v_owner,v_club_id,v_title,v_event_type,v_sport,v_discipline,v_location_text,v_city,p_starts_at[v_i],
        v_description,v_visibility,v_status,v_registration_enabled,v_round_deadline,
        v_max_participants,v_cover_image_url,p_series_id,v_i
      )
      returning id into v_event_id;
    else
      update public.events
      set club_id=v_club_id,title=v_title,event_type=v_event_type,sport=v_sport,
          discipline=v_discipline,location_text=v_location_text,city=v_city,
          starts_at=p_starts_at[v_i],description=v_description,visibility=v_visibility,
          status=v_status,registration_enabled=v_registration_enabled,
          registration_deadline=v_round_deadline,max_participants=v_max_participants,
          cover_image_url=v_cover_image_url
      where id=v_event_id;
    end if;

    if v_i=1 then v_first_event_id:=v_event_id; end if;
    v_event_ids:=v_event_ids||jsonb_build_array(v_event_id);
  end loop;

  return jsonb_build_object(
    'series_id',p_series_id,
    'first_event_id',v_first_event_id,
    'round_count',v_count,
    'event_ids',v_event_ids
  );
end;
$function$;

revoke execute on function public.create_event_series(jsonb,timestamptz[]) from public,anon;
revoke execute on function public.update_event_series(uuid,jsonb,timestamptz[]) from public,anon;
grant execute on function public.create_event_series(jsonb,timestamptz[]) to authenticated;
grant execute on function public.update_event_series(uuid,jsonb,timestamptz[]) to authenticated;

create or replace function public.notify_followers_event_published()
returns trigger
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare v_role text; v_name text;
begin
  if new.status='published' and new.visibility='public'
     and (new.series_id is null or new.series_round_number=1)
     and (tg_op='INSERT' or old.status is distinct from 'published' or old.visibility is distinct from 'public') then
    select role::text,coalesce(full_name,'Klub') into v_role,v_name from public.profiles where id=new.owner_id;
    if v_role in ('club','organization') then
      perform public.notify_followers_of_profile(
        new.owner_id,'followed_entity_event','event',new.id,
        'Nová udalosť',v_name||' vytvoril udalosť „'||new.title||'“.','/udalost/?id='||new.id::text
      );
    end if;
  end if;
  return new;
end;
$function$;

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
  select
    e.id,
    coalesce(c.name,p.full_name,'Connect Sports Pro') as club_name,
    case
      when e.series_id is not null then e.event_type||' · '||e.series_round_number::text||'. kolo'
      else e.event_type
    end as event_type,
    e.title,e.sport,e.discipline,e.starts_at,e.ends_at,e.city,e.location_text,e.cover_image_url
  from public.events e
  left join public.clubs c on c.id=e.club_id
  left join public.profiles p on p.id=e.owner_id
  where e.status='published'
    and e.visibility='public'
    and e.starts_at>=now()
  order by e.starts_at asc
  limit greatest(1,least(coalesce(p_limit,12),50));
$function$;

