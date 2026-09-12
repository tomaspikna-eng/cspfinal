create table if not exists public.event_preregistrations (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  full_name text not null,
  nickname text not null,
  consent_given boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.event_preregistrations enable row level security;

create unique index if not exists event_preregistrations_event_nickname_unique
  on public.event_preregistrations (event_id, lower(nickname));

create index if not exists event_preregistrations_event_created_idx
  on public.event_preregistrations (event_id, created_at);

revoke all on public.event_preregistrations from anon, authenticated;
grant select, delete on public.event_preregistrations to authenticated;

create policy event_preregistrations_owner_select
on public.event_preregistrations
for select
to authenticated
using (
  exists (
    select 1 from public.events e
    where e.id = event_id
      and e.owner_id = auth.uid()
  )
);

create policy event_preregistrations_owner_delete
on public.event_preregistrations
for delete
to authenticated
using (
  exists (
    select 1 from public.events e
    where e.id = event_id
      and e.owner_id = auth.uid()
  )
);

create or replace function public.submit_event_preregistration(
  p_event_id uuid,
  p_full_name text,
  p_nickname text,
  p_consent boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event public.events%rowtype;
  v_id uuid;
  v_count integer;
begin
  select * into v_event
  from public.events
  where id = p_event_id;

  if not found then
    raise exception 'Udalosť neexistuje.';
  end if;

  if v_event.status <> 'published' or v_event.visibility <> 'public' then
    raise exception 'Predregistrácia nie je dostupná.';
  end if;

  if not coalesce(v_event.registration_enabled, false) then
    raise exception 'Predregistrácia nie je zapnutá.';
  end if;

  if v_event.registration_deadline is not null and now() > v_event.registration_deadline then
    raise exception 'Predregistrácia už bola ukončená.';
  end if;

  if coalesce(trim(p_full_name), '') = '' then
    raise exception 'Zadaj meno a priezvisko.';
  end if;

  if coalesce(trim(p_nickname), '') = '' then
    raise exception 'Zadaj nickname.';
  end if;

  if length(trim(p_full_name)) > 120 or length(trim(p_nickname)) > 60 then
    raise exception 'Zadané údaje sú príliš dlhé.';
  end if;

  if not p_consent then
    raise exception 'Na odoslanie je potrebný súhlas so spracovaním údajov.';
  end if;

  if v_event.max_participants is not null then
    select count(*) into v_count
    from public.event_preregistrations
    where event_id = p_event_id;

    if v_count >= v_event.max_participants then
      raise exception 'Kapacita predregistrácie je naplnená.';
    end if;
  end if;

  insert into public.event_preregistrations(event_id, full_name, nickname, consent_given)
  values (p_event_id, trim(p_full_name), trim(p_nickname), true)
  returning id into v_id;

  return v_id;
exception
  when unique_violation then
    raise exception 'Tento nickname je už pre túto udalosť zaregistrovaný.';
end;
$$;

create or replace function public.get_public_event_preregistrations(p_event_id uuid)
returns table (
  nickname text,
  created_at timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select r.nickname, r.created_at
  from public.event_preregistrations r
  join public.events e on e.id = r.event_id
  where r.event_id = p_event_id
    and e.status = 'published'
    and e.visibility = 'public'
    and e.registration_enabled = true
  order by r.created_at asc;
$$;

create or replace function public.get_owner_event_preregistrations(p_event_id uuid)
returns table (
  id uuid,
  full_name text,
  nickname text,
  created_at timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select r.id, r.full_name, r.nickname, r.created_at
  from public.event_preregistrations r
  join public.events e on e.id = r.event_id
  where r.event_id = p_event_id
    and e.owner_id = auth.uid()
  order by r.created_at asc;
$$;

revoke all on function public.submit_event_preregistration(uuid,text,text,boolean) from public;
revoke all on function public.get_public_event_preregistrations(uuid) from public;
revoke all on function public.get_owner_event_preregistrations(uuid) from public;

grant execute on function public.submit_event_preregistration(uuid,text,text,boolean) to anon, authenticated;
grant execute on function public.get_public_event_preregistrations(uuid) to anon, authenticated;
grant execute on function public.get_owner_event_preregistrations(uuid) to authenticated;

