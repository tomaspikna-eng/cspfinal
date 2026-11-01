alter table public.teams
  add column if not exists is_present boolean not null default false;
