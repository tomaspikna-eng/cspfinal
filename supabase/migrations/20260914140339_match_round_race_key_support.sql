alter table public.matches add column if not exists race_to_key text;

update public.matches
set race_to_key = case
  when group_index is not null and round_number is not null then 'G:'||round_number::text
  when bracket_side='W' and round_number is not null then 'W:'||round_number::text
  when bracket_side='L' and round_number is not null then 'L:'||round_number::text
  when bracket_side='GF' then 'F:1'
  else race_to_key
end
where race_to_key is null;

comment on column public.matches.race_to_key is 'Frontend/server-neutral key identifying the tournament round/stage used for per-round race-to overrides.';

create index if not exists matches_tournament_race_to_key_idx on public.matches(tournament_id,race_to_key) where race_to_key is not null;
