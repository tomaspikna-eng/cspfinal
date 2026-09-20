alter table public.club_employees
  add column if not exists employee_code text,
  add column if not exists email text,
  add column if not exists phone text,
  add column if not exists photo_url text,
  add column if not exists vacation_days_total integer not null default 20,
  add column if not exists vacation_days_used integer not null default 0,
  add column if not exists sick_days_year integer not null default 0;

create unique index if not exists club_employees_club_code_uq
  on public.club_employees(club_id, employee_code)
  where employee_code is not null;

create table if not exists public.club_employee_schedule (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  employee_id uuid not null references public.club_employees(id) on delete cascade,
  work_date date not null,
  starts_at time,
  ends_at time,
  status text not null default 'shift'
    check (status in ('shift','off','vacation','sick')),
  station_label text,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(employee_id, work_date)
);

create index if not exists club_employee_schedule_club_date_idx
  on public.club_employee_schedule(club_id, work_date);

alter table public.club_employee_schedule enable row level security;

drop policy if exists club_employee_schedule_owner_all on public.club_employee_schedule;
create policy club_employee_schedule_owner_all on public.club_employee_schedule
for all to authenticated
using (
  exists(
    select 1 from public.clubs c
    where c.id=club_id and (c.owner_id=auth.uid() or public.is_admin(auth.uid()))
  )
)
with check (
  exists(
    select 1 from public.clubs c
    where c.id=club_id and (c.owner_id=auth.uid() or public.is_admin(auth.uid()))
  )
);

create or replace function public.club_manager_next_employee_code(p_club_id uuid)
returns text
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare
  v_uid uuid:=auth.uid();
  v_next integer;
begin
  if not exists(select 1 from public.clubs c where c.id=p_club_id and (c.owner_id=v_uid or public.is_admin(v_uid))) then
    raise exception 'CLUB_ACCESS_DENIED';
  end if;
  select coalesce(max(nullif(regexp_replace(employee_code,'\D','','g'),'')::int),0)+1
    into v_next
  from public.club_employees
  where club_id=p_club_id;
  return 'ZAM-'||lpad(v_next::text,4,'0');
end $$;

grant execute on function public.club_manager_next_employee_code(uuid) to authenticated;