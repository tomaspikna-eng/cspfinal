-- Billiard team-league workflow owned by identified PRO+/Ultra captains.
-- Organizers manage league structure and rosters, but cannot write lineups
-- or sporting results on behalf of a team captain.

alter table public.league_players
  add column if not exists captain_user_id uuid references public.profiles(id) on delete set null;

create index if not exists league_players_captain_user_idx
  on public.league_players(captain_user_id)
  where captain_user_id is not null;

alter table public.league_match_sheets
  alter column submitted_by drop not null,
  add column if not exists home_confirmed_by uuid references public.profiles(id) on delete set null,
  add column if not exists away_confirmed_by uuid references public.profiles(id) on delete set null,
  add column if not exists home_confirmed_at timestamptz,
  add column if not exists away_confirmed_at timestamptz;

alter table public.league_match_sheets
  drop constraint if exists league_match_sheets_status_check;
alter table public.league_match_sheets
  add constraint league_match_sheets_status_check
  check (status in ('draft','pending_confirmation','submitted','corrected'));

create or replace function public.is_league_team_captain(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
     and public.has_plan_at_least((select auth.uid()),'pro_plus')
     and exists (
       select 1
       from public.league_players lp
       where lp.id = p_team_id
         and lp.captain_user_id = (select auth.uid())
         and coalesce(lp.metadata ->> 'participant_type','') = 'team'
     );
$$;

revoke all on function public.is_league_team_captain(uuid) from public, anon, authenticated;
grant execute on function public.is_league_team_captain(uuid) to authenticated, service_role;

create or replace function public.is_league_captain_for_league(p_league_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
     and public.has_plan_at_least((select auth.uid()),'pro_plus')
     and exists (
       select 1 from public.league_players lp
       where lp.league_id=p_league_id
         and lp.captain_user_id=(select auth.uid())
         and coalesce(lp.metadata->>'participant_type','')='team'
     );
$$;

revoke all on function public.is_league_captain_for_league(uuid) from public,anon,authenticated;
grant execute on function public.is_league_captain_for_league(uuid) to authenticated,service_role;

create or replace function public.league_captain_match_side(p_match_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when public.is_league_team_captain(m.player1_id) then 'home'
    when public.is_league_team_captain(m.player2_id) then 'away'
    else null
  end
  from public.league_matches m
  where m.id = p_match_id;
$$;

revoke all on function public.league_captain_match_side(uuid) from public, anon, authenticated;
grant execute on function public.league_captain_match_side(uuid) to authenticated, service_role;

-- A captain must be able to read their team even while the league is draft/private.
drop policy if exists league_players_captain_read on public.league_players;
create policy league_players_captain_read
on public.league_players
for select
to authenticated
using (captain_user_id = (select auth.uid()));

-- Captains also need the opponent, match and league context before a private
-- league is published. These policies are read-only and do not grant the
-- organizer's management rights.
drop policy if exists leagues_team_captain_read on public.leagues;
create policy leagues_team_captain_read
on public.leagues
for select
to authenticated
using (
  public.is_league_captain_for_league(id)
);

drop policy if exists league_matches_team_captain_read on public.league_matches;
create policy league_matches_team_captain_read
on public.league_matches
for select
to authenticated
using (
  public.is_league_team_captain(player1_id)
  or public.is_league_team_captain(player2_id)
);

drop policy if exists league_players_match_captain_read on public.league_players;
create policy league_players_match_captain_read
on public.league_players
for select
to authenticated
using (
  exists (
    select 1
    from public.league_matches m
    where (m.player1_id = league_players.id or m.player2_id = league_players.id)
      and (
        public.is_league_team_captain(m.player1_id)
        or public.is_league_team_captain(m.player2_id)
      )
  )
);

drop policy if exists league_match_lineups_manage on public.league_match_lineups;
drop policy if exists league_match_sheets_manager_insert on public.league_match_sheets;
drop policy if exists league_match_sheets_manager_update on public.league_match_sheets;

drop policy if exists league_match_lineups_captain_read on public.league_match_lineups;
create policy league_match_lineups_captain_read
on public.league_match_lineups
for select
to authenticated
using (public.league_captain_match_side(match_id) is not null);

drop policy if exists league_match_sheets_captain_read on public.league_match_sheets;
create policy league_match_sheets_captain_read
on public.league_match_sheets
for select
to authenticated
using (public.league_captain_match_side(match_id) is not null);

revoke insert, update, delete on public.league_match_lineups from authenticated;
revoke insert, update, delete on public.league_match_sheets from authenticated;

drop function if exists public.submit_league_match_sheet(uuid,date,text,text,text,boolean,boolean,jsonb,text);

create or replace function public.save_league_captain_lineup(
  p_match_id uuid,
  p_slots jsonb,
  p_doubles_slots smallint[]
)
returns public.league_match_lineups
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_match public.league_matches%rowtype;
  v_side text;
  v_team_id uuid;
  v_row public.league_match_lineups%rowtype;
begin
  v_side := public.league_captain_match_side(p_match_id);
  if v_side is null then
    raise exception 'Zostavu môže uložiť iba kapitán tímu s plánom PRO+ alebo Ultra.';
  end if;
  select * into v_match from public.league_matches where id = p_match_id;
  if not found then raise exception 'Ligový zápas neexistuje.'; end if;
  if jsonb_typeof(p_slots) <> 'array' or jsonb_array_length(p_slots) < 2 then
    raise exception 'Nominácia musí obsahovať aspoň dvoch hráčov.';
  end if;
  if cardinality(coalesce(p_doubles_slots,'{}'::smallint[])) <> 2 then
    raise exception 'Kapitán musí označiť presne dvoch hráčov pre zápas dvojíc.';
  end if;
  v_team_id := case when v_side = 'home' then v_match.player1_id else v_match.player2_id end;

  insert into public.league_match_lineups(match_id,side,team_id,slots,doubles_slots,updated_by)
  values(p_match_id,v_side,v_team_id,p_slots,coalesce(p_doubles_slots,'{}'::smallint[]),(select auth.uid()))
  on conflict(match_id,side) do update set
    team_id=excluded.team_id,
    slots=excluded.slots,
    doubles_slots=excluded.doubles_slots,
    updated_by=(select auth.uid()),
    updated_at=now()
  returning * into v_row;

  update public.league_match_sheets set
    rubbers='[]'::jsonb,
    home_captain_confirmed=false,
    away_captain_confirmed=false,
    home_confirmed_by=null,
    away_confirmed_by=null,
    home_confirmed_at=null,
    away_confirmed_at=null,
    home_points=0,
    away_points=0,
    status='draft',
    updated_at=now()
  where match_id=p_match_id;

  if v_match.status in ('completed','pending_confirmation') then
    update public.league_matches set
      score1=null,score2=null,winner_id=null,result_type=null,
      status='pending_confirmation',confirmed_by=null,confirmed_at=null,completed_at=null
    where id=p_match_id;
  end if;
  return v_row;
end;
$$;

revoke all on function public.save_league_captain_lineup(uuid,jsonb,smallint[]) from public, anon, authenticated;
grant execute on function public.save_league_captain_lineup(uuid,jsonb,smallint[]) to authenticated, service_role;

create or replace function public.save_league_billiard_sheet(
  p_match_id uuid,
  p_played_on date,
  p_venue text,
  p_rubbers jsonb,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_match public.league_matches%rowtype;
  v_league public.leagues%rowtype;
  v_home_team public.league_players%rowtype;
  v_away_team public.league_players%rowtype;
  v_home_lineup public.league_match_lineups%rowtype;
  v_away_lineup public.league_match_lineups%rowtype;
  v_side text;
  v_rubber jsonb;
  v_expected integer;
  v_home_name text;
  v_away_name text;
  v_home_captain text;
  v_away_captain text;
begin
  v_side := public.league_captain_match_side(p_match_id);
  if v_side is null then
    raise exception 'Zápis môže meniť iba kapitán tímu s plánom PRO+ alebo Ultra.';
  end if;
  select * into v_match from public.league_matches where id=p_match_id;
  select * into v_league from public.leagues where id=v_match.league_id;
  if v_match.id is null or v_league.id is null then raise exception 'Ligový zápas neexistuje.'; end if;
  if public.normalize_ihs_sport(v_league.sport) <> 'billiards' then
    raise exception 'Tento typ zápisu je určený pre biliardovú ligu.';
  end if;
  select * into v_home_team from public.league_players where id=v_match.player1_id;
  select * into v_away_team from public.league_players where id=v_match.player2_id;
  if v_home_team.captain_user_id is null or v_away_team.captain_user_id is null then
    raise exception 'Oba tímy musia mať priradeného kapitána s CSP profilom.';
  end if;
  if v_home_team.captain_user_id = v_away_team.captain_user_id then
    raise exception 'Domáci a hostia musia mať rozdielnych kapitánov.';
  end if;
  select * into v_home_lineup from public.league_match_lineups where match_id=p_match_id and side='home';
  select * into v_away_lineup from public.league_match_lineups where match_id=p_match_id and side='away';
  if v_home_lineup.match_id is null or v_away_lineup.match_id is null then
    raise exception 'Najprv musia obaja kapitáni uložiť svoje zostavy.';
  end if;
  if cardinality(v_home_lineup.doubles_slots) <> 2 or cardinality(v_away_lineup.doubles_slots) <> 2 then
    raise exception 'Obaja kapitáni musia označiť presne dvoch hráčov pre zápas dvojíc.';
  end if;
  if p_played_on is null then raise exception 'Doplň dátum zápasu.'; end if;
  if jsonb_typeof(p_rubbers)<>'array' or jsonb_array_length(p_rubbers)<1 or jsonb_array_length(p_rubbers)>24 then
    raise exception 'Zápis musí obsahovať 1 až 24 zápasov.';
  end if;
  if (
    select count(*) <> count(distinct (x.value->>'number')::integer)
    from jsonb_array_elements(p_rubbers) x(value)
    where coalesce(x.value->>'number','') ~ '^[1-9][0-9]*$'
  ) or exists(
    select 1 from jsonb_array_elements(p_rubbers) x(value)
    where jsonb_typeof(x.value)<>'object' or coalesce(x.value->>'number','') !~ '^[1-9][0-9]*$'
  ) then raise exception 'Poradie zápasov nie je platné.'; end if;

  for v_rubber in select value from jsonb_array_elements(p_rubbers)
  loop
    if v_rubber->>'type' not in ('singles','doubles') then raise exception 'Neplatný typ zápasu.'; end if;
    v_expected := case when v_rubber->>'type'='doubles' then 2 else 1 end;
    if btrim(coalesce(v_rubber->>'discipline',''))=''
       or jsonb_typeof(v_rubber->'home_players')<>'array'
       or jsonb_typeof(v_rubber->'away_players')<>'array'
       or jsonb_array_length(v_rubber->'home_players')<>v_expected
       or jsonb_array_length(v_rubber->'away_players')<>v_expected then
      raise exception 'Zápas č. % nemá kompletné údaje.',v_rubber->>'number';
    end if;
    if exists(
      select 1 from jsonb_array_elements_text(v_rubber->'home_players') p(name)
      where not exists(select 1 from jsonb_array_elements(v_home_lineup.slots) s where s->>'name'=p.name)
    ) or exists(
      select 1 from jsonb_array_elements_text(v_rubber->'away_players') p(name)
      where not exists(select 1 from jsonb_array_elements(v_away_lineup.slots) s where s->>'name'=p.name)
    ) then raise exception 'Zápas č. % obsahuje hráča mimo nominácie.',v_rubber->>'number'; end if;
    if v_expected=2 and (
      exists(
        select 1 from jsonb_array_elements_text(v_rubber->'home_players') p(name)
        where not exists(
          select 1 from jsonb_array_elements(v_home_lineup.slots) s
          where s->>'name'=p.name and (s->>'slot')::smallint=any(v_home_lineup.doubles_slots)
        )
      ) or exists(
        select 1 from jsonb_array_elements_text(v_rubber->'away_players') p(name)
        where not exists(
          select 1 from jsonb_array_elements(v_away_lineup.slots) s
          where s->>'name'=p.name and (s->>'slot')::smallint=any(v_away_lineup.doubles_slots)
        )
      )
    ) then raise exception 'Dvojica nezodpovedá označeniu kapitánov.'; end if;
    if (
      select count(*)<>count(distinct p.name) from jsonb_array_elements_text(v_rubber->'home_players') p(name)
    ) or (
      select count(*)<>count(distinct p.name) from jsonb_array_elements_text(v_rubber->'away_players') p(name)
    ) then raise exception 'V dvojici nemôže byť hráč uvedený dvakrát.'; end if;
    if (v_rubber ? 'home_score') <> (v_rubber ? 'away_score') then
      raise exception 'Výsledok musí obsahovať obe strany.';
    end if;
    if v_rubber ? 'home_score' and (
      coalesce(v_rubber->>'home_score','') not in ('0','1')
      or coalesce(v_rubber->>'away_score','') not in ('0','1')
      or (v_rubber->>'home_score')::integer+(v_rubber->>'away_score')::integer<>1
    ) then raise exception 'Výsledok zápasu musí byť 1:0 alebo 0:1.'; end if;
  end loop;

  if (
    select count(*) from jsonb_array_elements(p_rubbers) x where x->>'type'='singles'
  ) <> jsonb_array_length(v_home_lineup.slots)
     or jsonb_array_length(v_home_lineup.slots)<>jsonb_array_length(v_away_lineup.slots) then
    raise exception 'Každý nominovaný hráč musí mať práve jeden single zápas.';
  end if;
  if (
    select count(distinct p.name)
    from jsonb_array_elements(p_rubbers) x
    cross join lateral jsonb_array_elements_text(x->'home_players') p(name)
    where x->>'type'='singles'
  ) <> jsonb_array_length(v_home_lineup.slots)
  or (
    select count(distinct p.name)
    from jsonb_array_elements(p_rubbers) x
    cross join lateral jsonb_array_elements_text(x->'away_players') p(name)
    where x->>'type'='singles'
  ) <> jsonb_array_length(v_away_lineup.slots) then
    raise exception 'Hráč nemôže byť v single zápasoch použitý opakovane.';
  end if;
  if (select count(*) from jsonb_array_elements(p_rubbers) x where x->>'type'='doubles')<>1 then
    raise exception 'Zápis musí obsahovať jeden zápas dvojíc.';
  end if;

  select coalesce(nullif(btrim(p.full_name),''),nullif(btrim(v_home_team.metadata->>'captain'),''),'Kapitán domácich')
    into v_home_captain from public.profiles p where p.id=v_home_team.captain_user_id;
  select coalesce(nullif(btrim(p.full_name),''),nullif(btrim(v_away_team.metadata->>'captain'),''),'Kapitán hostí')
    into v_away_captain from public.profiles p where p.id=v_away_team.captain_user_id;

  insert into public.league_match_sheets(
    match_id,played_on,venue,home_captain,away_captain,rubbers,notes,status,
    home_captain_confirmed,away_captain_confirmed,home_confirmed_by,away_confirmed_by,
    home_confirmed_at,away_confirmed_at,home_points,away_points,submitted_by,submitted_at,updated_at
  ) values (
    p_match_id,p_played_on,nullif(btrim(coalesce(p_venue,'')),''),v_home_captain,v_away_captain,p_rubbers,
    nullif(btrim(coalesce(p_notes,'')),''),'draft',false,false,null,null,null,null,0,0,(select auth.uid()),now(),now()
  )
  on conflict(match_id) do update set
    played_on=excluded.played_on,venue=excluded.venue,home_captain=excluded.home_captain,
    away_captain=excluded.away_captain,rubbers=excluded.rubbers,notes=excluded.notes,status='draft',
    home_captain_confirmed=false,away_captain_confirmed=false,home_confirmed_by=null,away_confirmed_by=null,
    home_confirmed_at=null,away_confirmed_at=null,home_points=0,away_points=0,
    submitted_by=(select auth.uid()),submitted_at=now(),updated_at=now();

  update public.league_matches set
    score1=null,score2=null,winner_id=null,result_type=null,status='pending_confirmation',
    reported_by=(select auth.uid()),reported_at=now(),confirmed_by=null,confirmed_at=null,completed_at=null
  where id=p_match_id;

  return jsonb_build_object('match_id',p_match_id,'side',v_side,'status','draft');
end;
$$;

revoke all on function public.save_league_billiard_sheet(uuid,date,text,jsonb,text) from public, anon, authenticated;
grant execute on function public.save_league_billiard_sheet(uuid,date,text,jsonb,text) to authenticated, service_role;

create or replace function public.confirm_league_billiard_sheet(p_match_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_side text;
  v_sheet public.league_match_sheets%rowtype;
  v_home_points integer;
  v_away_points integer;
begin
  v_side:=public.league_captain_match_side(p_match_id);
  if v_side is null then raise exception 'Zápis môže potvrdiť iba kapitán s plánom PRO+ alebo Ultra.'; end if;
  select * into v_sheet from public.league_match_sheets where match_id=p_match_id for update;
  if not found then raise exception 'Najprv ulož zápis zápasu.'; end if;
  if jsonb_array_length(v_sheet.rubbers)<1 or exists(
    select 1 from jsonb_array_elements(v_sheet.rubbers) x(value)
    where coalesce(x.value->>'home_score','') not in ('0','1')
       or coalesce(x.value->>'away_score','') not in ('0','1')
       or (x.value->>'home_score')::integer+(x.value->>'away_score')::integer<>1
  ) then raise exception 'Pred potvrdením doplň všetky výsledky.'; end if;

  if v_side='home' then
    update public.league_match_sheets set home_captain_confirmed=true,home_confirmed_by=(select auth.uid()),home_confirmed_at=now(),status='pending_confirmation',updated_at=now() where match_id=p_match_id;
  else
    update public.league_match_sheets set away_captain_confirmed=true,away_confirmed_by=(select auth.uid()),away_confirmed_at=now(),status='pending_confirmation',updated_at=now() where match_id=p_match_id;
  end if;
  select * into v_sheet from public.league_match_sheets where match_id=p_match_id;

  if v_sheet.home_captain_confirmed and v_sheet.away_captain_confirmed then
    select coalesce(sum((x.value->>'home_score')::integer),0),coalesce(sum((x.value->>'away_score')::integer),0)
      into v_home_points,v_away_points from jsonb_array_elements(v_sheet.rubbers) x(value);
    update public.league_match_sheets set home_points=v_home_points,away_points=v_away_points,status='submitted',updated_at=now() where match_id=p_match_id;
    update public.league_matches set
      score1=v_home_points,score2=v_away_points,
      winner_id=case when v_home_points>v_away_points then player1_id when v_away_points>v_home_points then player2_id else null end,
      result_type=case when v_home_points=v_away_points then 'draw' else 'normal' end,
      status='completed',confirmed_by=(select auth.uid()),confirmed_at=now(),completed_at=now()
    where id=p_match_id;
    return jsonb_build_object('status','submitted','home_points',v_home_points,'away_points',v_away_points,'home_confirmed',true,'away_confirmed',true);
  end if;
  return jsonb_build_object('status','pending_confirmation','home_confirmed',v_sheet.home_captain_confirmed,'away_confirmed',v_sheet.away_captain_confirmed);
end;
$$;

revoke all on function public.confirm_league_billiard_sheet(uuid) from public, anon, authenticated;
grant execute on function public.confirm_league_billiard_sheet(uuid) to authenticated, service_role;

-- Fixed league tablets. A station is logistics only: it may point to one
-- rubber, but score writes still require an authenticated eligible captain.
create table if not exists public.league_resources (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  resource_number integer not null check (resource_number > 0),
  label text not null,
  device_token uuid not null default gen_random_uuid(),
  current_match_id uuid references public.league_matches(id) on delete set null,
  current_rubber_number integer check (current_rubber_number is null or current_rubber_number > 0),
  is_active boolean not null default true,
  tablet_last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(league_id,resource_number),
  unique(device_token)
);

create unique index if not exists league_resources_one_rubber_station_idx
  on public.league_resources(current_match_id,current_rubber_number)
  where current_match_id is not null;

alter table public.league_resources enable row level security;
drop policy if exists league_resources_manager_all on public.league_resources;
create policy league_resources_manager_all
on public.league_resources for all to authenticated
using (public.can_manage_league(league_id))
with check (public.can_manage_league(league_id));

drop policy if exists league_resources_captain_read on public.league_resources;
create policy league_resources_captain_read
on public.league_resources for select to authenticated
using (
  public.is_league_captain_for_league(league_id)
);

revoke all on table public.league_resources from public, anon, authenticated;
grant select,insert,update,delete on table public.league_resources to authenticated;

create or replace function public.configure_league_resources(
  p_league_id uuid,
  p_count integer,
  p_label_prefix text default 'Biliardový stôl'
)
returns setof public.league_resources
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  i integer;
  v_prefix text:=coalesce(nullif(btrim(p_label_prefix),''),'Biliardový stôl');
begin
  if not public.can_manage_league(p_league_id) or not public.has_plan_at_least((select auth.uid()),'pro_plus') then
    raise exception 'Stanice môže nastaviť iba správca ligy s plánom PRO+ alebo Ultra.';
  end if;
  if p_count is null or p_count<1 or p_count>64 then raise exception 'Počet staníc musí byť od 1 do 64.'; end if;
  for i in 1..p_count loop
    insert into public.league_resources(league_id,resource_number,label)
    values(p_league_id,i,v_prefix||' '||lpad(i::text,2,'0'))
    on conflict(league_id,resource_number) do update set label=excluded.label,is_active=true,updated_at=now();
  end loop;
  update public.league_resources set is_active=false,current_match_id=null,current_rubber_number=null,updated_at=now()
  where league_id=p_league_id and resource_number>p_count;
  return query select * from public.league_resources where league_id=p_league_id and is_active order by resource_number;
end;
$$;

revoke all on function public.configure_league_resources(uuid,integer,text) from public,anon,authenticated;
grant execute on function public.configure_league_resources(uuid,integer,text) to authenticated,service_role;

create or replace function public.assign_league_rubber_station(p_match_id uuid,p_rubber_number integer,p_resource_id uuid)
returns public.league_resources
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_match public.league_matches%rowtype;
  v_resource public.league_resources%rowtype;
  v_rubber_count integer;
begin
  select * into v_match from public.league_matches where id=p_match_id;
  if not found then raise exception 'Ligový zápas neexistuje.'; end if;
  if not ((public.can_manage_league(v_match.league_id) and public.has_plan_at_least((select auth.uid()),'pro_plus')) or public.league_captain_match_side(p_match_id) is not null) then
    raise exception 'Stanicu môže priradiť iba správca ligy alebo kapitán s plánom PRO+ alebo Ultra.';
  end if;
  if p_rubber_number is null or p_rubber_number<1 then raise exception 'Neplatné číslo duelu.'; end if;
  select jsonb_array_length(s.rubbers) into v_rubber_count from public.league_match_sheets s where s.match_id=p_match_id;
  if coalesce(v_rubber_count,0)<p_rubber_number then raise exception 'Duel č. % v zápise neexistuje.',p_rubber_number; end if;
  select * into v_resource from public.league_resources where id=p_resource_id and league_id=v_match.league_id and is_active;
  if not found then raise exception 'Stanica nepatrí do tejto ligy.'; end if;
  update public.league_resources set current_match_id=null,current_rubber_number=null,updated_at=now()
  where current_match_id=p_match_id and current_rubber_number=p_rubber_number and id<>p_resource_id;
  update public.league_resources set current_match_id=p_match_id,current_rubber_number=p_rubber_number,updated_at=now()
  where id=p_resource_id returning * into v_resource;
  return v_resource;
end;
$$;

revoke all on function public.assign_league_rubber_station(uuid,integer,uuid) from public,anon,authenticated;
grant execute on function public.assign_league_rubber_station(uuid,integer,uuid) to authenticated,service_role;

create or replace function public.get_league_station_state(p_device_token uuid)
returns table(resource_id uuid,resource_label text,league_id uuid,league_name text,match_id uuid,rubber_number integer,home_team text,away_team text)
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_resource public.league_resources%rowtype;
begin
  select * into v_resource from public.league_resources where device_token=p_device_token and is_active;
  if not found then raise exception 'Ligová stanica neexistuje alebo je vypnutá.'; end if;
  if not ((public.can_manage_league(v_resource.league_id) and public.has_plan_at_least((select auth.uid()),'pro_plus')) or public.is_league_captain_for_league(v_resource.league_id)) then
    raise exception 'Na ligovej stanici sa prihlás ako správca alebo kapitán s plánom PRO+.';
  end if;
  update public.league_resources set tablet_last_seen_at=now(),updated_at=now() where id=v_resource.id;
  return query select r.id,r.label,r.league_id,l.name,m.id,r.current_rubber_number,h.display_name,a.display_name
  from public.league_resources r
  join public.leagues l on l.id=r.league_id
  left join public.league_matches m on m.id=r.current_match_id
  left join public.league_players h on h.id=m.player1_id
  left join public.league_players a on a.id=m.player2_id
  where r.id=v_resource.id;
end;
$$;

revoke all on function public.get_league_station_state(uuid) from public,anon,authenticated;
grant execute on function public.get_league_station_state(uuid) to authenticated,service_role;
