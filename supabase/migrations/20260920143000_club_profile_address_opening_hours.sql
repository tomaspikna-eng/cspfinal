alter table public.clubs
  add column if not exists address_line1 text,
  add column if not exists postal_code text,
  add column if not exists city text,
  add column if not exists country text,
  add column if not exists opening_hours jsonb not null default '{}'::jsonb;

comment on column public.clubs.opening_hours is
'Club opening hours keyed by mon,tue,wed,thu,fri,sat,sun; each value is a display range such as 18:00-01:00 or closed.';