alter table public.event_preregistrations
  add column if not exists user_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.event_preregistrations'::regclass
      and conname='event_preregistrations_user_id_fkey'
  ) then
    alter table public.event_preregistrations
      add constraint event_preregistrations_user_id_fkey
      foreign key (user_id) references public.profiles(id) on delete set null;
  end if;
end $$;

create index if not exists event_preregistrations_user_id_idx
  on public.event_preregistrations(user_id)
  where user_id is not null;

with unique_profile_names as (
  select lower(trim(full_name)) as normalized_name, min(id::text)::uuid as user_id
  from public.profiles
  where nullif(trim(full_name),'') is not null
  group by lower(trim(full_name))
  having count(*)=1
)
update public.event_preregistrations r
set user_id=u.user_id
from unique_profile_names u
where r.user_id is null
  and lower(trim(r.full_name))=u.normalized_name;

update public.tournament_players tp
set user_id=r.user_id
from public.tournaments t
join public.event_preregistrations r
  on r.event_id=t.source_event_id
 and r.user_id is not null
where tp.tournament_id=t.id
  and tp.user_id is null
  and lower(trim(tp.name))=lower(trim(r.full_name));

create or replace function public.submit_event_preregistration(
  p_event_id uuid,
  p_full_name text,
  p_nickname text,
  p_consent boolean
) returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_event public.events%rowtype;
  v_id uuid;
  v_count integer;
  v_user_id uuid;
begin
  select * into v_event from public.events where id=p_event_id;
  if not found then raise exception 'Udalosť neexistuje.'; end if;
  if v_event.status <> 'published' or v_event.visibility <> 'public' then raise exception 'Predregistrácia nie je dostupná.'; end if;
  if not coalesce(v_event.registration_enabled,false) then raise exception 'Predregistrácia nie je zapnutá.'; end if;
  if v_event.registration_deadline is not null and now()>v_event.registration_deadline then raise exception 'Predregistrácia už bola ukončená.'; end if;
  if coalesce(trim(p_full_name),'')='' then raise exception 'Zadaj meno a priezvisko.'; end if;
  if coalesce(trim(p_nickname),'')='' then raise exception 'Zadaj nickname.'; end if;
  if length(trim(p_full_name))>120 or length(trim(p_nickname))>60 then raise exception 'Zadané údaje sú príliš dlhé.'; end if;
  if not p_consent then raise exception 'Na odoslanie je potrebný súhlas so spracovaním údajov.'; end if;

  if v_event.max_participants is not null then
    select count(*) into v_count from public.event_preregistrations where event_id=p_event_id;
    if v_count>=v_event.max_participants then raise exception 'Kapacita predregistrácie je naplnená.'; end if;
  end if;

  select p.id into v_user_id from public.profiles p where p.id=auth.uid();

  insert into public.event_preregistrations(event_id,full_name,nickname,consent_given,user_id)
  values(p_event_id,trim(p_full_name),trim(p_nickname),true,v_user_id)
  returning id into v_id;
  return v_id;
exception
  when unique_violation then raise exception 'Tento nickname je už pre túto udalosť zaregistrovaný.';
end;
$function$;

create or replace function public.export_event_to_tournament(
  p_event_id uuid,
  p_format text default 'sko'::text,
  p_groups_count integer default null::integer,
  p_advance_count integer default null::integer
) returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_event public.events;
  v_tournament public.tournaments;
  v_player_count integer:=0;
  v_registration record;
begin
  select * into v_event from public.events
  where id=p_event_id and (owner_id=auth.uid() or public.is_admin(auth.uid()))
  for update;
  if v_event.id is null then raise exception 'EVENT_NOT_FOUND_OR_ACCESS_DENIED'; end if;
  if coalesce(v_event.sport,'')='' or coalesce(v_event.discipline,'')='' then raise exception 'EVENT_SPORT_AND_DISCIPLINE_REQUIRED'; end if;
  if p_format not in ('rr','sko','dko','rr_sko','rr_dko','karty') then raise exception 'INVALID_TOURNAMENT_FORMAT'; end if;

  select * into v_tournament from public.tournaments where source_event_id=v_event.id for update;
  if v_tournament.id is null then
    insert into public.tournaments(
      owner_id,name,sport,discipline,format,date,venue,groups_count,advance_count,status,config,city,
      visibility,registration_enabled,registration_deadline,max_participants,source_event_id
    ) values (
      v_event.owner_id,v_event.title,v_event.sport,v_event.discipline,p_format,
      (v_event.starts_at at time zone 'Europe/Bratislava')::date,v_event.location_text,
      p_groups_count,p_advance_count,'draft',
      jsonb_build_object(
        'source_event_id',v_event.id,'source_event_description',v_event.description,
        'source_event_starts_at',v_event.starts_at,'source_event_ends_at',v_event.ends_at,
        'source_event_type',v_event.event_type,'source_event_cover_image_url',v_event.cover_image_url
      ),
      v_event.city,v_event.visibility,v_event.registration_enabled,v_event.registration_deadline,
      v_event.max_participants,v_event.id
    ) returning * into v_tournament;
  else
    update public.tournaments
    set name=v_event.title,sport=v_event.sport,discipline=v_event.discipline,
        format=coalesce(p_format,format),date=(v_event.starts_at at time zone 'Europe/Bratislava')::date,
        venue=v_event.location_text,groups_count=coalesce(p_groups_count,groups_count),
        advance_count=coalesce(p_advance_count,advance_count),city=v_event.city,
        visibility=v_event.visibility,registration_enabled=v_event.registration_enabled,
        registration_deadline=v_event.registration_deadline,max_participants=v_event.max_participants,
        config=coalesce(config,'{}'::jsonb) || jsonb_build_object(
          'source_event_id',v_event.id,'source_event_description',v_event.description,
          'source_event_starts_at',v_event.starts_at,'source_event_ends_at',v_event.ends_at,
          'source_event_type',v_event.event_type,'source_event_cover_image_url',v_event.cover_image_url
        ),
        updated_at=now()
    where id=v_tournament.id
    returning * into v_tournament;
  end if;

  for v_registration in
    select distinct on (lower(trim(coalesce(nullif(r.full_name,''),r.nickname))))
      trim(coalesce(nullif(r.full_name,''),r.nickname)) as player_name,r.user_id
    from public.event_preregistrations r
    where r.event_id=v_event.id and trim(coalesce(nullif(r.full_name,''),r.nickname))<>''
    order by lower(trim(coalesce(nullif(r.full_name,''),r.nickname))),(r.user_id is not null) desc,r.created_at asc
  loop
    update public.tournament_players tp
    set user_id=coalesce(tp.user_id,v_registration.user_id)
    where tp.tournament_id=v_tournament.id
      and ((v_registration.user_id is not null and tp.user_id=v_registration.user_id)
           or lower(trim(tp.name))=lower(v_registration.player_name));

    if not found then
      insert into public.tournament_players(tournament_id,name,user_id)
      values(v_tournament.id,v_registration.player_name,v_registration.user_id);
    end if;
  end loop;

  select count(*) into v_player_count from public.tournament_players where tournament_id=v_tournament.id;
  return jsonb_build_object(
    'tournament_id',v_tournament.id,'source_event_id',v_event.id,
    'player_count',v_player_count,'tournament_status',v_tournament.status
  );
end;
$function$;

create or replace function public.sync_draft_tournament_players(
  p_tournament_id uuid,
  p_players jsonb
) returns setof public.tournament_players
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_status text;
  item jsonb;
  n integer:=0;
  v_user_id uuid;
begin
  select status into v_status
  from public.tournaments t
  where t.id=p_tournament_id and (t.owner_id=auth.uid() or public.is_admin(auth.uid()))
  for update;
  if v_status is null then raise exception 'Tournament not found or access denied'; end if;
  if v_status not in ('draft','ready') or exists(select 1 from public.matches m where m.tournament_id=p_tournament_id) then
    raise exception 'Player list is locked after matches are created or tournament starts';
  end if;

  delete from public.tournament_groups where tournament_id=p_tournament_id;
  delete from public.tournament_players where tournament_id=p_tournament_id;

  for item in select * from jsonb_array_elements(coalesce(p_players,'[]'::jsonb))
  loop
    n:=n+1;
    v_user_id:=nullif(item->>'user_id','')::uuid;
    insert into public.tournament_players(tournament_id,name,user_id,seed)
    values(p_tournament_id,nullif(trim(item->>'name'),''),v_user_id,coalesce((item->>'seed')::integer,n));
  end loop;

  return query select * from public.tournament_players where tournament_id=p_tournament_id order by seed;
end;
$function$;
