-- Team league match lineups: D/H slots, per-slot discipline and doubles selection.

create table if not exists public.league_match_lineups (
  match_id uuid not null references public.league_matches(id) on delete cascade,
  side text not null check (side in ('home','away')),
  team_id uuid not null references public.league_players(id) on delete cascade,
  slots jsonb not null default '[]'::jsonb,
  doubles_slots smallint[] not null default '{}'::smallint[],
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (match_id, side),
  constraint league_match_lineups_slots_array check (jsonb_typeof(slots) = 'array'),
  constraint league_match_lineups_doubles_count check (cardinality(doubles_slots) in (0, 2))
);

create index if not exists league_match_lineups_team_idx
  on public.league_match_lineups(team_id);

create or replace function public.validate_league_match_lineup()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_match public.league_matches%rowtype;
  v_expected_team uuid;
begin
  select * into v_match
  from public.league_matches
  where id = new.match_id;

  if not found then
    raise exception 'League match not found.';
  end if;

  v_expected_team := case when new.side = 'home' then v_match.player1_id else v_match.player2_id end;
  if v_expected_team is null or new.team_id is distinct from v_expected_team then
    raise exception 'Lineup team does not match the selected match side.';
  end if;

  if jsonb_array_length(new.slots) > 12 then
    raise exception 'Too many lineup slots.';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(new.slots) as x(value)
    where jsonb_typeof(x.value) <> 'object'
       or not (x.value ? 'slot')
       or not (x.value ? 'name')
       or not (x.value ? 'discipline')
  ) then
    raise exception 'Invalid lineup slot payload.';
  end if;

  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end;
$$;

revoke all on function public.validate_league_match_lineup() from public, anon, authenticated;

drop trigger if exists trg_validate_league_match_lineup on public.league_match_lineups;
create trigger trg_validate_league_match_lineup
before insert or update on public.league_match_lineups
for each row execute function public.validate_league_match_lineup();

alter table public.league_match_lineups enable row level security;

drop policy if exists league_match_lineups_public_read on public.league_match_lineups;
create policy league_match_lineups_public_read
on public.league_match_lineups
for select
to public
using (
  exists (
    select 1
    from public.league_matches m
    join public.leagues l on l.id = m.league_id
    where m.id = league_match_lineups.match_id
      and (
        (l.visibility in ('public','unlisted') and l.status <> 'draft')
        or public.can_manage_league(l.id)
      )
  )
);

drop policy if exists league_match_lineups_manage on public.league_match_lineups;
create policy league_match_lineups_manage
on public.league_match_lineups
for all
to authenticated
using (
  exists (
    select 1 from public.league_matches m
    where m.id = league_match_lineups.match_id
      and public.can_manage_league(m.league_id)
  )
)
with check (
  exists (
    select 1 from public.league_matches m
    where m.id = league_match_lineups.match_id
      and public.can_manage_league(m.league_id)
  )
);

revoke all on table public.league_match_lineups from public, anon, authenticated;
grant select on table public.league_match_lineups to anon, authenticated;
grant insert, update, delete on table public.league_match_lineups to authenticated;
