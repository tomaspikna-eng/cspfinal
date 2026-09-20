drop policy if exists club_employee_leave_requests_manager_all
on public.club_employee_leave_requests;

create policy club_employee_leave_requests_manager_all
on public.club_employee_leave_requests
for all
to authenticated
using (
  exists (
    select 1
    from public.clubs c
    where c.id = club_employee_leave_requests.club_id
      and (c.owner_id = auth.uid() or public.is_admin(auth.uid()))
  )
)
with check (
  exists (
    select 1
    from public.clubs c
    where c.id = club_employee_leave_requests.club_id
      and (c.owner_id = auth.uid() or public.is_admin(auth.uid()))
  )
);