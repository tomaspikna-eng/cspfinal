alter table public.club_employees
  add column if not exists activation_sent_at timestamptz,
  add column if not exists account_activated_at timestamptz,
  add column if not exists activation_email_sent_to text;

create or replace function public.club_employee_complete_activation()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_employee public.club_employees;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  update public.club_employees
  set account_activated_at = coalesce(account_activated_at, now()),
      updated_at = now()
  where auth_user_id = auth.uid()
    and is_active = true
  returning * into v_employee;

  if v_employee.id is null then
    raise exception 'EMPLOYEE_LINK_NOT_FOUND';
  end if;

  return jsonb_build_object(
    'ok', true,
    'employee_id', v_employee.id,
    'club_id', v_employee.club_id,
    'employee_code', v_employee.employee_code,
    'activated_at', v_employee.account_activated_at
  );
end;
$$;

revoke all on function public.club_employee_complete_activation() from public;
grant execute on function public.club_employee_complete_activation() to authenticated;
grant execute on function public.club_employee_complete_activation() to service_role;