create table if not exists public.csp_beta_testers (
  slot integer primary key check (slot between 1 and 100),
  profile_id uuid not null unique references public.profiles(id) on delete cascade,
  email text not null,
  full_name text not null,
  status text not null default 'active' check (status in ('active','inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.csp_beta_testers enable row level security;

revoke all on public.csp_beta_testers from anon, authenticated;
