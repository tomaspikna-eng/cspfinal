create table if not exists public.club_employee_leave_requests (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  employee_id uuid not null references public.club_employees(id) on delete cascade,
  request_type text not null check (request_type in ('vacation','sick')),
  start_date date not null,
  end_date date not null,
  note text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  requested_by uuid references auth.users(id) on delete set null,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  manager_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (end_date >= start_date)
);

create index if not exists club_employee_leave_requests_club_idx
  on public.club_employee_leave_requests(club_id,status,start_date);
create index if not exists club_employee_leave_requests_employee_idx
  on public.club_employee_leave_requests(employee_id,start_date);

alter table public.club_employee_leave_requests enable row level security;

drop policy if exists club_employee_leave_requests_manager_all on public.club_employee_leave_requests;
create policy club_employee_leave_requests_manager_all
on public.club_employee_leave_requests
for all
to authenticated
using (
  exists (
    select 1 from public.clubs c
    left join public.profiles p on p.id = auth.uid()
    where c.id = club_employee_leave_requests.club_id
      and (c.owner_id = auth.uid() or coalesce(p.is_admin,false))
  )
)
with check (
  exists (
    select 1 from public.clubs c
    left join public.profiles p on p.id = auth.uid()
    where c.id = club_employee_leave_requests.club_id
      and (c.owner_id = auth.uid() or coalesce(p.is_admin,false))
  )
);

drop policy if exists club_employee_leave_requests_employee_select on public.club_employee_leave_requests;
create policy club_employee_leave_requests_employee_select
on public.club_employee_leave_requests
for select
to authenticated
using (
  exists (
    select 1 from public.club_employees ce
    where ce.id = club_employee_leave_requests.employee_id
      and ce.auth_user_id = auth.uid()
  )
);

drop policy if exists club_employee_leave_requests_employee_insert on public.club_employee_leave_requests;
create policy club_employee_leave_requests_employee_insert
on public.club_employee_leave_requests
for insert
to authenticated
with check (
  status = 'pending'
  and exists (
    select 1 from public.club_employees ce
    where ce.id = club_employee_leave_requests.employee_id
      and ce.club_id = club_employee_leave_requests.club_id
      and ce.auth_user_id = auth.uid()
  )
);