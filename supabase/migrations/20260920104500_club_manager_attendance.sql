alter table public.clubs
  add column if not exists attendance_enabled boolean not null default false;

create table if not exists public.club_employees (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  full_name text not null,
  role_name text,
  hourly_rate numeric(10,2),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists club_employees_club_idx on public.club_employees(club_id,is_active);

create table if not exists public.club_attendance_sessions (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  employee_id uuid not null references public.club_employees(id) on delete cascade,
  clock_in_at timestamptz not null default now(),
  clock_out_at timestamptz,
  break_started_at timestamptz,
  break_seconds integer not null default 0,
  status text not null default 'working' check (status in ('working','break','completed')),
  note text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists club_attendance_sessions_club_idx on public.club_attendance_sessions(club_id,clock_in_at);
create index if not exists club_attendance_sessions_employee_idx on public.club_attendance_sessions(employee_id,clock_in_at);

alter table public.club_employees enable row level security;
alter table public.club_attendance_sessions enable row level security;

drop policy if exists club_employees_owner_all on public.club_employees;
create policy club_employees_owner_all on public.club_employees
for all to authenticated
using (exists(select 1 from public.clubs c where c.id=club_id and (c.owner_id=auth.uid() or public.is_admin(auth.uid()))))
with check (exists(select 1 from public.clubs c where c.id=club_id and (c.owner_id=auth.uid() or public.is_admin(auth.uid()))));

drop policy if exists club_attendance_owner_all on public.club_attendance_sessions;
create policy club_attendance_owner_all on public.club_attendance_sessions
for all to authenticated
using (exists(select 1 from public.clubs c where c.id=club_id and (c.owner_id=auth.uid() or public.is_admin(auth.uid()))))
with check (exists(select 1 from public.clubs c where c.id=club_id and (c.owner_id=auth.uid() or public.is_admin(auth.uid()))));

create or replace function public.club_manager_set_attendance_enabled(p_enabled boolean)
returns boolean
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare v_uid uuid:=auth.uid(); v_club uuid;
begin
  select c.id into v_club from public.clubs c where c.owner_id=v_uid limit 1;
  if v_club is null and not public.is_admin(v_uid) then raise exception 'CLUB_ACCESS_DENIED'; end if;
  if v_club is null then select id into v_club from public.clubs order by created_at limit 1; end if;
  update public.clubs set attendance_enabled=p_enabled where id=v_club;
  return p_enabled;
end $$;

create or replace function public.club_manager_attendance_clock_in(p_employee_id uuid)
returns uuid language plpgsql security definer set search_path='public','pg_temp' as $$
declare v_uid uuid:=auth.uid(); v_club uuid; v_id uuid;
begin
  select club_id into v_club from public.club_employees where id=p_employee_id and is_active;
  if v_club is null then raise exception 'EMPLOYEE_NOT_FOUND'; end if;
  if not exists(select 1 from public.clubs c where c.id=v_club and (c.owner_id=v_uid or public.is_admin(v_uid))) then raise exception 'CLUB_ACCESS_DENIED'; end if;
  if exists(select 1 from public.club_attendance_sessions s where s.employee_id=p_employee_id and s.status in ('working','break')) then raise exception 'ALREADY_CLOCKED_IN'; end if;
  insert into public.club_attendance_sessions(club_id,employee_id,created_by) values(v_club,p_employee_id,v_uid) returning id into v_id;
  return v_id;
end $$;

create or replace function public.club_manager_attendance_toggle_break(p_session_id uuid)
returns text language plpgsql security definer set search_path='public','pg_temp' as $$
declare v_uid uuid:=auth.uid(); s public.club_attendance_sessions;
begin
  select * into s from public.club_attendance_sessions where id=p_session_id;
  if not found then raise exception 'SESSION_NOT_FOUND'; end if;
  if not exists(select 1 from public.clubs c where c.id=s.club_id and (c.owner_id=v_uid or public.is_admin(v_uid))) then raise exception 'CLUB_ACCESS_DENIED'; end if;
  if s.status='working' then
    update public.club_attendance_sessions set status='break',break_started_at=now(),updated_at=now() where id=p_session_id;
    return 'break';
  elsif s.status='break' then
    update public.club_attendance_sessions
      set status='working',
          break_seconds=break_seconds+greatest(0,extract(epoch from (now()-break_started_at))::int),
          break_started_at=null,updated_at=now()
      where id=p_session_id;
    return 'working';
  end if;
  raise exception 'SESSION_COMPLETED';
end $$;

create or replace function public.club_manager_attendance_clock_out(p_session_id uuid)
returns boolean language plpgsql security definer set search_path='public','pg_temp' as $$
declare v_uid uuid:=auth.uid(); s public.club_attendance_sessions; extra integer:=0;
begin
  select * into s from public.club_attendance_sessions where id=p_session_id;
  if not found then raise exception 'SESSION_NOT_FOUND'; end if;
  if not exists(select 1 from public.clubs c where c.id=s.club_id and (c.owner_id=v_uid or public.is_admin(v_uid))) then raise exception 'CLUB_ACCESS_DENIED'; end if;
  if s.status='break' and s.break_started_at is not null then extra:=greatest(0,extract(epoch from(now()-s.break_started_at))::int); end if;
  update public.club_attendance_sessions set clock_out_at=now(),break_seconds=break_seconds+extra,break_started_at=null,status='completed',updated_at=now() where id=p_session_id;
  return true;
end $$;

grant execute on function public.club_manager_set_attendance_enabled(boolean) to authenticated;
grant execute on function public.club_manager_attendance_clock_in(uuid) to authenticated;
grant execute on function public.club_manager_attendance_toggle_break(uuid) to authenticated;
grant execute on function public.club_manager_attendance_clock_out(uuid) to authenticated;