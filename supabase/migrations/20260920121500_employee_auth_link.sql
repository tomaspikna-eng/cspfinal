alter table public.club_employees
  add column if not exists auth_user_id uuid references auth.users(id) on delete set null;

create unique index if not exists club_employees_auth_user_uq
  on public.club_employees(auth_user_id)
  where auth_user_id is not null;