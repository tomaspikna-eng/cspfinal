begin;

alter table public.club_manager_live_sessions
  add column if not exists station_name_snapshot text,
  add column if not exists station_sport_snapshot text;

alter table public.reservations
  add column if not exists station_name_snapshot text,
  add column if not exists station_sport_snapshot text;

update public.club_manager_live_sessions s
set station_name_snapshot = coalesce(s.station_name_snapshot, st.name),
    station_sport_snapshot = coalesce(s.station_sport_snapshot, st.sport)
from public.stations st
where st.id = s.station_id;

update public.reservations r
set station_name_snapshot = coalesce(r.station_name_snapshot, st.name),
    station_sport_snapshot = coalesce(r.station_sport_snapshot, st.sport)
from public.stations st
where st.id = r.station_id;

create or replace function public.fill_station_snapshot()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.station_id is not null then
    select st.name, st.sport
      into new.station_name_snapshot, new.station_sport_snapshot
    from public.stations st
    where st.id = new.station_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_live_sessions_station_snapshot on public.club_manager_live_sessions;
create trigger trg_live_sessions_station_snapshot
before insert or update of station_id on public.club_manager_live_sessions
for each row execute function public.fill_station_snapshot();

drop trigger if exists trg_reservations_station_snapshot on public.reservations;
create trigger trg_reservations_station_snapshot
before insert or update of station_id on public.reservations
for each row execute function public.fill_station_snapshot();

alter table public.club_manager_live_sessions
  alter column station_id drop not null;

alter table public.reservations
  alter column station_id drop not null;

alter table public.club_manager_live_sessions
  drop constraint if exists club_manager_live_sessions_station_id_fkey;

alter table public.club_manager_live_sessions
  add constraint club_manager_live_sessions_station_id_fkey
  foreign key (station_id) references public.stations(id) on delete set null;

alter table public.reservations
  drop constraint if exists reservations_station_id_fkey;

alter table public.reservations
  add constraint reservations_station_id_fkey
  foreign key (station_id) references public.stations(id) on delete set null;

commit;

