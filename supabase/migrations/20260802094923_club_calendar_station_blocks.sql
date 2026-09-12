create table if not exists public.calendar_station_blocks (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  station_id uuid not null references public.stations(id) on delete cascade,
  event_id uuid null references public.events(id) on delete set null,
  tournament_id uuid null references public.tournaments(id) on delete set null,
  label text not null,
  block_type text not null default 'tournament' check (block_type in ('tournament','maintenance','manual')),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint calendar_station_blocks_valid_time check (ends_at > starts_at)
);

create index if not exists calendar_station_blocks_club_time_idx on public.calendar_station_blocks(club_id, starts_at, ends_at);
create index if not exists calendar_station_blocks_station_time_idx on public.calendar_station_blocks(station_id, starts_at, ends_at);

alter table public.calendar_station_blocks enable row level security;

drop policy if exists calendar_station_blocks_select on public.calendar_station_blocks;
create policy calendar_station_blocks_select on public.calendar_station_blocks for select using (
  exists(select 1 from public.clubs c where c.id=club_id and (c.owner_id=auth.uid() or public.is_admin(auth.uid())))
);

drop policy if exists calendar_station_blocks_write on public.calendar_station_blocks;
create policy calendar_station_blocks_write on public.calendar_station_blocks for all using (
  exists(select 1 from public.clubs c where c.id=club_id and (c.owner_id=auth.uid() or public.is_admin(auth.uid())))
) with check (
  exists(select 1 from public.clubs c where c.id=club_id and (c.owner_id=auth.uid() or public.is_admin(auth.uid())))
);

create or replace function public.club_manager_upsert_station_block(
  p_block_id uuid,
  p_club_id uuid,
  p_station_id uuid,
  p_event_id uuid,
  p_tournament_id uuid,
  p_label text,
  p_block_type text,
  p_starts_at timestamptz,
  p_ends_at timestamptz
) returns uuid
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;
begin
  if not exists(select 1 from public.clubs c where c.id=p_club_id and (c.owner_id=auth.uid() or public.is_admin(auth.uid()))) then
    raise exception 'ACCESS_DENIED';
  end if;
  if p_ends_at<=p_starts_at then raise exception 'INVALID_TIME_RANGE'; end if;
  if exists(select 1 from public.reservations r where r.station_id=p_station_id and r.status in ('pending','confirmed','checked_in') and tstzrange(r.starts_at,r.ends_at,'[)') && tstzrange(p_starts_at,p_ends_at,'[)')) then
    raise exception 'STATION_HAS_RESERVATION';
  end if;
  if p_block_id is null then
    insert into public.calendar_station_blocks(club_id,station_id,event_id,tournament_id,label,block_type,starts_at,ends_at)
    values(p_club_id,p_station_id,p_event_id,p_tournament_id,trim(p_label),coalesce(p_block_type,'tournament'),p_starts_at,p_ends_at)
    returning id into v_id;
  else
    update public.calendar_station_blocks set station_id=p_station_id,event_id=p_event_id,tournament_id=p_tournament_id,label=trim(p_label),block_type=coalesce(p_block_type,'tournament'),starts_at=p_starts_at,ends_at=p_ends_at,updated_at=now()
    where id=p_block_id and club_id=p_club_id returning id into v_id;
  end if;
  return v_id;
end;$$;

grant execute on function public.club_manager_upsert_station_block(uuid,uuid,uuid,uuid,uuid,text,text,timestamptz,timestamptz) to authenticated;

create or replace function public.prevent_reservation_on_station_block() returns trigger
language plpgsql set search_path=public,pg_temp as $$
begin
  if new.status in ('pending','confirmed','checked_in') and exists(
    select 1 from public.calendar_station_blocks b
    where b.station_id=new.station_id
      and tstzrange(b.starts_at,b.ends_at,'[)') && tstzrange(new.starts_at,new.ends_at,'[)')
  ) then
    raise exception 'STATION_BLOCKED_BY_TOURNAMENT_OR_EVENT';
  end if;
  return new;
end;$$;

drop trigger if exists trg_prevent_reservation_on_station_block on public.reservations;
create trigger trg_prevent_reservation_on_station_block before insert or update of station_id,starts_at,ends_at,status on public.reservations for each row execute function public.prevent_reservation_on_station_block();

