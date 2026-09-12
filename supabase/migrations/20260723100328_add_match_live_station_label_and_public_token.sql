alter table public.matches add column if not exists station_label text; alter table public.matches add column if not exists public_token uuid not null default gen_random_uuid(); create unique index if not exists matches_public_token_uidx on public.matches(public_token);

