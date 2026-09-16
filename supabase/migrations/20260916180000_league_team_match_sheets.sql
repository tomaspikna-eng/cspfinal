-- Complete team-league match sheet. Captains choose the actual pairings;
-- the submitted sheet is the durable source for who played whom.

create table if not exists public.league_match_sheets (
  match_id uuid primary key references public.league_matches(id) on delete cascade,
  played_on date not null default current_date,
  venue text,
  home_captain text not null,
  away_captain text not null,
  home_captain_confirmed boolean not null default false,
  away_captain_confirmed boolean not null default false,
  rubbers jsonb not null default '[]'::jsonb,
  home_points integer not null default 0 check (home_points >= 0),
  away_points integer not null default 0 check (away_points >= 0),
  notes text,
  status text not null default 'submitted' check (status in ('submitted','corrected')),
  submitted_by uuid not null references public.profiles(id) on delete restrict,
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint league_match_sheets_rubbers_array check (jsonb_typeof(rubbers) = 'array')
);

create index if not exists league_match_sheets_submitted_by_idx
  on public.league_match_sheets(submitted_by);

alter table public.league_match_sheets enable row level security;

drop policy if exists league_match_sheets_public_read on public.league_match_sheets;
create policy league_match_sheets_public_read
on public.league_match_sheets
for select
to anon, authenticated
using (
  exists (
    select 1
    from public.league_matches m
    join public.leagues l on l.id = m.league_id
    where m.id = league_match_sheets.match_id
      and (
        (l.visibility in ('public','unlisted') and l.status <> 'draft')
        or public.can_manage_league(l.id)
      )
  )
);

drop policy if exists league_match_sheets_manager_insert on public.league_match_sheets;
create policy league_match_sheets_manager_insert
on public.league_match_sheets
for insert
to authenticated
with check (
  submitted_by = (select auth.uid())
  and exists (
    select 1 from public.league_matches m
    where m.id = league_match_sheets.match_id
      and public.can_manage_league(m.league_id)
  )
);

drop policy if exists league_match_sheets_manager_update on public.league_match_sheets;
create policy league_match_sheets_manager_update
on public.league_match_sheets
for update
to authenticated
using (
  exists (
    select 1 from public.league_matches m
    where m.id = league_match_sheets.match_id
      and public.can_manage_league(m.league_id)
  )
)
with check (
  submitted_by = (select auth.uid())
  and exists (
    select 1 from public.league_matches m
    where m.id = league_match_sheets.match_id
      and public.can_manage_league(m.league_id)
  )
);

revoke all on table public.league_match_sheets from public, anon, authenticated;
grant select on table public.league_match_sheets to anon, authenticated;
grant insert, update on table public.league_match_sheets to authenticated;

create or replace function public.submit_league_match_sheet(
  p_match_id uuid,
  p_played_on date,
  p_venue text,
  p_home_captain text,
  p_away_captain text,
  p_home_confirmed boolean,
  p_away_confirmed boolean,
  p_rubbers jsonb,
  p_notes text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_match public.league_matches%rowtype;
  v_league public.leagues%rowtype;
  v_home_team public.league_players%rowtype;
  v_away_team public.league_players%rowtype;
  v_home_members jsonb;
  v_away_members jsonb;
  v_rubber jsonb;
  v_type text;
  v_home_score integer;
  v_away_score integer;
  v_home_points integer := 0;
  v_away_points integer := 0;
  v_expected_players integer;
  v_existing boolean := false;
begin
  if (select auth.uid()) is null then
    raise exception 'Na odoslanie zápisu sa prihlás.';
  end if;

  select * into v_match from public.league_matches where id = p_match_id;
  if not found then raise exception 'Ligový zápas neexistuje.'; end if;
  if not public.can_manage_league(v_match.league_id) then
    raise exception 'Zápis môže odoslať iba správca ligy.';
  end if;

  select * into v_league from public.leagues where id = v_match.league_id;
  if coalesce(v_league.config ->> 'participant_type','player') <> 'team' then
    raise exception 'Zápis tímového zápasu patrí iba do tímovej ligy.';
  end if;

  select * into v_home_team from public.league_players where id = v_match.player1_id and league_id = v_match.league_id;
  select * into v_away_team from public.league_players where id = v_match.player2_id and league_id = v_match.league_id;
  if v_home_team.id is null or v_away_team.id is null then raise exception 'Tímy zápasu sa nenašli.'; end if;

  v_home_members := coalesce(v_home_team.metadata -> 'members','[]'::jsonb);
  v_away_members := coalesce(v_away_team.metadata -> 'members','[]'::jsonb);
  if jsonb_typeof(v_home_members) <> 'array' or jsonb_typeof(v_away_members) <> 'array' then
    raise exception 'Súpisky tímov nie sú platné.';
  end if;

  if btrim(coalesce(p_home_captain,'')) = '' or btrim(coalesce(p_away_captain,'')) = '' then
    raise exception 'Doplň oboch kapitánov.';
  end if;
  if not coalesce(p_home_confirmed,false) or not coalesce(p_away_confirmed,false) then
    raise exception 'Zápis musia potvrdiť obaja kapitáni.';
  end if;
  if p_played_on is null then raise exception 'Doplň dátum zápasu.'; end if;
  if jsonb_typeof(p_rubbers) <> 'array' or jsonb_array_length(p_rubbers) < 1 or jsonb_array_length(p_rubbers) > 24 then
    raise exception 'Zápis musí obsahovať 1 až 24 duelov.';
  end if;
  if (
    select count(*) <> count(distinct (x.value ->> 'number')::integer)
    from jsonb_array_elements(p_rubbers) as x(value)
    where coalesce(x.value ->> 'number','') ~ '^[1-9][0-9]*$'
  ) or exists (
    select 1 from jsonb_array_elements(p_rubbers) as x(value)
    where jsonb_typeof(x.value) <> 'object'
       or coalesce(x.value ->> 'number','') !~ '^[1-9][0-9]*$'
  ) then
    raise exception 'Poradie duelov nie je platné.';
  end if;

  for v_rubber in select value from jsonb_array_elements(p_rubbers)
  loop
    v_type := v_rubber ->> 'type';
    if v_type not in ('singles','doubles') then raise exception 'Neplatný typ duelu.'; end if;
    v_expected_players := case when v_type = 'doubles' then 2 else 1 end;
    if btrim(coalesce(v_rubber ->> 'discipline','')) = ''
       or jsonb_typeof(v_rubber -> 'home_players') <> 'array'
       or jsonb_typeof(v_rubber -> 'away_players') <> 'array'
       or jsonb_array_length(v_rubber -> 'home_players') <> v_expected_players
       or jsonb_array_length(v_rubber -> 'away_players') <> v_expected_players then
      raise exception 'Duel č. % nemá kompletné údaje.', v_rubber ->> 'number';
    end if;
    if exists (
      select 1 from jsonb_array_elements_text(v_rubber -> 'home_players') p(name)
      where btrim(p.name) = '' or not (v_home_members ? p.name)
    ) or exists (
      select 1 from jsonb_array_elements_text(v_rubber -> 'away_players') p(name)
      where btrim(p.name) = '' or not (v_away_members ? p.name)
    ) then
      raise exception 'Duel č. % obsahuje hráča mimo súpisky.', v_rubber ->> 'number';
    end if;
    if (
      select count(*) <> count(distinct p.name)
      from jsonb_array_elements_text(v_rubber -> 'home_players') p(name)
    ) or (
      select count(*) <> count(distinct p.name)
      from jsonb_array_elements_text(v_rubber -> 'away_players') p(name)
    ) then
      raise exception 'V jednej dvojici nemôže byť hráč uvedený dvakrát.';
    end if;
    if coalesce(v_rubber ->> 'home_score','') !~ '^[0-9]+$'
       or coalesce(v_rubber ->> 'away_score','') !~ '^[0-9]+$' then
      raise exception 'Duel č. % nemá platné skóre.', v_rubber ->> 'number';
    end if;
    v_home_score := (v_rubber ->> 'home_score')::integer;
    v_away_score := (v_rubber ->> 'away_score')::integer;
    if v_home_score = v_away_score then
      raise exception 'Duel č. % musí mať víťaza.', v_rubber ->> 'number';
    elsif v_home_score > v_away_score then
      v_home_points := v_home_points + 1;
    else
      v_away_points := v_away_points + 1;
    end if;
  end loop;

  select exists(select 1 from public.league_match_sheets where match_id = p_match_id) into v_existing;
  insert into public.league_match_sheets(
    match_id,played_on,venue,home_captain,away_captain,
    home_captain_confirmed,away_captain_confirmed,rubbers,
    home_points,away_points,notes,status,submitted_by,submitted_at,updated_at
  ) values (
    p_match_id,p_played_on,nullif(btrim(coalesce(p_venue,'')),''),btrim(p_home_captain),btrim(p_away_captain),
    true,true,p_rubbers,v_home_points,v_away_points,nullif(btrim(coalesce(p_notes,'')),''),
    case when v_existing then 'corrected' else 'submitted' end,(select auth.uid()),now(),now()
  )
  on conflict (match_id) do update set
    played_on = excluded.played_on,
    venue = excluded.venue,
    home_captain = excluded.home_captain,
    away_captain = excluded.away_captain,
    home_captain_confirmed = true,
    away_captain_confirmed = true,
    rubbers = excluded.rubbers,
    home_points = excluded.home_points,
    away_points = excluded.away_points,
    notes = excluded.notes,
    status = 'corrected',
    submitted_by = excluded.submitted_by,
    submitted_at = now(),
    updated_at = now();

  update public.league_matches set
    score1 = v_home_points,
    score2 = v_away_points,
    winner_id = case when v_home_points > v_away_points then player1_id when v_away_points > v_home_points then player2_id else null end,
    result_type = case when v_home_points = v_away_points then 'draw' else 'normal' end,
    status = 'completed',
    reported_by = (select auth.uid()),
    reported_at = now(),
    confirmed_by = (select auth.uid()),
    confirmed_at = now(),
    completed_at = now()
  where id = p_match_id;

  return jsonb_build_object(
    'match_id',p_match_id,
    'home_points',v_home_points,
    'away_points',v_away_points,
    'status',case when v_existing then 'corrected' else 'submitted' end
  );
end;
$$;

revoke all on function public.submit_league_match_sheet(uuid,date,text,text,text,boolean,boolean,jsonb,text) from public, anon, authenticated;
grant execute on function public.submit_league_match_sheet(uuid,date,text,text,text,boolean,boolean,jsonb,text) to authenticated;
