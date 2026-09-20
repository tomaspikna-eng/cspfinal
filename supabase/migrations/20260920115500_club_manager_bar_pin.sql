alter table public.club_employees
  add column if not exists pin_hash text;

create or replace function public.club_manager_set_employee_pin(p_employee_id uuid, p_pin text)
returns boolean
language plpgsql
security definer
set search_path='public','extensions','pg_temp'
as $$
declare
  v_uid uuid:=auth.uid();
  v_club uuid;
begin
  if p_pin !~ '^[0-9]{4,6}$' then
    raise exception 'PIN_FORMAT';
  end if;
  select club_id into v_club from public.club_employees where id=p_employee_id;
  if v_club is null then raise exception 'EMPLOYEE_NOT_FOUND'; end if;
  if not exists(select 1 from public.clubs c where c.id=v_club and (c.owner_id=v_uid or public.is_admin(v_uid))) then
    raise exception 'CLUB_ACCESS_DENIED';
  end if;
  update public.club_employees
     set pin_hash=crypt(p_pin,gen_salt('bf')),updated_at=now()
   where id=p_employee_id;
  return true;
end $$;

create or replace function public.club_manager_employee_pin_login(p_employee_id uuid, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path='public','extensions','pg_temp'
as $$
declare
  v_uid uuid:=auth.uid();
  e public.club_employees;
  s public.club_attendance_sessions;
begin
  select * into e from public.club_employees where id=p_employee_id and is_active=true;
  if not found then raise exception 'EMPLOYEE_NOT_FOUND'; end if;
  if not exists(select 1 from public.clubs c where c.id=e.club_id and (c.owner_id=v_uid or public.is_admin(v_uid))) then
    raise exception 'CLUB_ACCESS_DENIED';
  end if;
  if e.pin_hash is null or crypt(p_pin,e.pin_hash)<>e.pin_hash then
    raise exception 'PIN_INVALID';
  end if;
  select * into s
    from public.club_attendance_sessions
   where employee_id=e.id and status in ('working','break')
   order by clock_in_at desc limit 1;

  if not found then
    insert into public.club_attendance_sessions(club_id,employee_id,created_by)
    values(e.club_id,e.id,v_uid)
    returning * into s;
  end if;

  return jsonb_build_object(
    'employee_id',e.id,
    'employee_name',e.full_name,
    'role_name',e.role_name,
    'session_id',s.id,
    'status',s.status,
    'clock_in_at',s.clock_in_at
  );
end $$;

create or replace function public.club_manager_employee_pin_clock_out(p_employee_id uuid, p_pin text)
returns boolean
language plpgsql
security definer
set search_path='public','extensions','pg_temp'
as $$
declare
  v_uid uuid:=auth.uid();
  e public.club_employees;
  s public.club_attendance_sessions;
  extra integer:=0;
begin
  select * into e from public.club_employees where id=p_employee_id and is_active=true;
  if not found then raise exception 'EMPLOYEE_NOT_FOUND'; end if;
  if not exists(select 1 from public.clubs c where c.id=e.club_id and (c.owner_id=v_uid or public.is_admin(v_uid))) then
    raise exception 'CLUB_ACCESS_DENIED';
  end if;
  if e.pin_hash is null or crypt(p_pin,e.pin_hash)<>e.pin_hash then raise exception 'PIN_INVALID'; end if;

  select * into s from public.club_attendance_sessions
  where employee_id=e.id and status in ('working','break')
  order by clock_in_at desc limit 1;
  if not found then raise exception 'NO_ACTIVE_SHIFT'; end if;

  if s.status='break' and s.break_started_at is not null then
    extra:=greatest(0,extract(epoch from(now()-s.break_started_at))::int);
  end if;

  update public.club_attendance_sessions
     set clock_out_at=now(),
         break_seconds=break_seconds+extra,
         break_started_at=null,
         status='completed',
         updated_at=now()
   where id=s.id;
  return true;
end $$;

grant execute on function public.club_manager_set_employee_pin(uuid,text) to authenticated;
grant execute on function public.club_manager_employee_pin_login(uuid,text) to authenticated;
grant execute on function public.club_manager_employee_pin_clock_out(uuid,text) to authenticated;