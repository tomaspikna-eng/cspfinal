-- Teams module for PRO+ and ULTRA.
-- Applied to production on 2026-10-25; this file keeps the schema reproducible.

create or replace function public.can_use_teams()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.plan in ('pro_plus'::profile_plan,'ultra'::profile_plan)
  );
$$;
revoke all on function public.can_use_teams() from public, anon;
grant execute on function public.can_use_teams() to authenticated;

create table if not exists public.teams (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 2 and 80),
  short_name text check (short_name is null or char_length(trim(short_name)) between 1 and 16),
  sport text not null default 'Biliard',
  city text,
  country text,
  logo_url text,
  status text not null default 'active' check (status in ('active','inactive','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.team_members (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete set null,
  display_name text not null check (char_length(trim(display_name)) between 2 and 100),
  member_role text not null default 'player' check (member_role in ('captain','player','substitute')),
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists team_members_unique_linked_user on public.team_members(team_id,user_id) where user_id is not null;
create index if not exists team_members_team_idx on public.team_members(team_id,active,sort_order);

create table if not exists public.team_competitions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 2 and 120),
  sport text not null default 'Biliard',
  season_name text,
  status text not null default 'draft' check (status in ('draft','active','completed','archived')),
  default_best_of integer not null default 5 check (default_best_of between 1 and 31 and mod(default_best_of,2)=1),
  default_discipline text not null default '9-ball',
  default_race_to integer not null default 5 check (default_race_to between 1 and 100),
  win_points integer not null default 3 check (win_points between 0 and 20),
  loss_points integer not null default 0 check (loss_points between 0 and 20),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.team_competition_teams (
  competition_id uuid not null references public.team_competitions(id) on delete cascade,
  team_id uuid not null references public.teams(id) on delete cascade,
  seed integer,
  created_at timestamptz not null default now(),
  primary key (competition_id,team_id)
);

create table if not exists public.team_meetings (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.team_competitions(id) on delete cascade,
  round_label text,
  scheduled_at timestamptz,
  home_team_id uuid not null references public.teams(id) on delete restrict,
  away_team_id uuid not null references public.teams(id) on delete restrict,
  best_of integer not null default 5 check (best_of between 1 and 31 and mod(best_of,2)=1),
  status text not null default 'scheduled' check (status in ('scheduled','active','completed','cancelled')),
  home_score integer not null default 0 check (home_score >= 0),
  away_score integer not null default 0 check (away_score >= 0),
  winner_team_id uuid references public.teams(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (home_team_id <> away_team_id)
);
create index if not exists team_meetings_competition_idx on public.team_meetings(competition_id,scheduled_at);

create table if not exists public.team_match_games (
  id uuid primary key default gen_random_uuid(),
  meeting_id uuid not null references public.team_meetings(id) on delete cascade,
  slot_no integer not null check (slot_no between 1 and 31),
  discipline text not null default '9-ball',
  race_to integer not null default 5 check (race_to between 1 and 100),
  home_member_id uuid references public.team_members(id) on delete set null,
  away_member_id uuid references public.team_members(id) on delete set null,
  home_score integer not null default 0 check (home_score >= 0),
  away_score integer not null default 0 check (away_score >= 0),
  status text not null default 'scheduled' check (status in ('scheduled','active','completed','cancelled')),
  winner_member_id uuid references public.team_members(id) on delete set null,
  winner_team_id uuid references public.teams(id) on delete set null,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(meeting_id,slot_no),
  check (home_member_id is null or away_member_id is null or home_member_id <> away_member_id)
);
create index if not exists team_match_games_meeting_idx on public.team_match_games(meeting_id,slot_no);

create or replace function public.create_team_meeting_games()
returns trigger language plpgsql set search_path = public, pg_temp as $$
declare v_discipline text; v_race_to integer;
begin
  select default_discipline,default_race_to into v_discipline,v_race_to
  from public.team_competitions where id=new.competition_id;
  insert into public.team_match_games(meeting_id,slot_no,discipline,race_to)
  select new.id,g,coalesce(v_discipline,'9-ball'),coalesce(v_race_to,5)
  from generate_series(1,new.best_of) g
  on conflict(meeting_id,slot_no) do nothing;
  return new;
end;
$$;

create or replace function public.sync_team_game_winner()
returns trigger language plpgsql set search_path = public, pg_temp as $$
declare m public.team_meetings;
begin
  select * into m from public.team_meetings where id=new.meeting_id;
  if m.id is null then raise exception 'Team meeting not found'; end if;
  if new.home_member_id is not null and not exists(select 1 from public.team_members tm where tm.id=new.home_member_id and tm.team_id=m.home_team_id) then raise exception 'Home player is not on the home team'; end if;
  if new.away_member_id is not null and not exists(select 1 from public.team_members tm where tm.id=new.away_member_id and tm.team_id=m.away_team_id) then raise exception 'Away player is not on the away team'; end if;
  if new.status='completed' then
    if new.home_member_id is null or new.away_member_id is null then raise exception 'Completed duel requires both players'; end if;
    if new.home_score=new.away_score then raise exception 'Completed duel cannot end in a draw'; end if;
    if greatest(new.home_score,new.away_score)<new.race_to then raise exception 'Winner must reach Race to %',new.race_to; end if;
    if new.home_score>new.away_score then new.winner_team_id:=m.home_team_id;new.winner_member_id:=new.home_member_id;
    else new.winner_team_id:=m.away_team_id;new.winner_member_id:=new.away_member_id;end if;
    new.completed_at:=coalesce(new.completed_at,now());
  else
    new.winner_team_id:=null;new.winner_member_id:=null;new.completed_at:=null;
  end if;
  return new;
end;
$$;

create or replace function public.refresh_team_meeting_score()
returns trigger language plpgsql set search_path = public, pg_temp as $$
declare v_meeting_id uuid;v_home uuid;v_away uuid;v_best integer;v_home_score integer;v_away_score integer;v_needed integer;
begin
  v_meeting_id:=coalesce(new.meeting_id,old.meeting_id);
  select home_team_id,away_team_id,best_of into v_home,v_away,v_best from public.team_meetings where id=v_meeting_id;
  if v_home is null then return coalesce(new,old);end if;
  select count(*) filter(where status='completed' and winner_team_id=v_home),count(*) filter(where status='completed' and winner_team_id=v_away)
  into v_home_score,v_away_score from public.team_match_games where meeting_id=v_meeting_id;
  v_needed:=floor(v_best/2.0)::integer+1;
  update public.team_meetings set
    home_score=v_home_score,away_score=v_away_score,
    status=case when v_home_score>=v_needed or v_away_score>=v_needed then 'completed' when v_home_score+v_away_score>0 then 'active' else status end,
    winner_team_id=case when v_home_score>=v_needed then v_home when v_away_score>=v_needed then v_away else null end,
    updated_at=now()
  where id=v_meeting_id;
  return coalesce(new,old);
end;
$$;

drop trigger if exists trg_create_team_meeting_games on public.team_meetings;
create trigger trg_create_team_meeting_games after insert on public.team_meetings for each row execute function public.create_team_meeting_games();
drop trigger if exists trg_sync_team_game_winner on public.team_match_games;
create trigger trg_sync_team_game_winner before insert or update of status,home_score,away_score,home_member_id,away_member_id on public.team_match_games for each row execute function public.sync_team_game_winner();
drop trigger if exists trg_refresh_team_meeting_score on public.team_match_games;
create trigger trg_refresh_team_meeting_score after insert or update or delete on public.team_match_games for each row execute function public.refresh_team_meeting_score();

drop trigger if exists teams_set_updated_at on public.teams;
create trigger teams_set_updated_at before update on public.teams for each row execute function public.set_updated_at();
drop trigger if exists team_members_set_updated_at on public.team_members;
create trigger team_members_set_updated_at before update on public.team_members for each row execute function public.set_updated_at();
drop trigger if exists team_competitions_set_updated_at on public.team_competitions;
create trigger team_competitions_set_updated_at before update on public.team_competitions for each row execute function public.set_updated_at();
drop trigger if exists team_meetings_set_updated_at on public.team_meetings;
create trigger team_meetings_set_updated_at before update on public.team_meetings for each row execute function public.set_updated_at();
drop trigger if exists team_match_games_set_updated_at on public.team_match_games;
create trigger team_match_games_set_updated_at before update on public.team_match_games for each row execute function public.set_updated_at();

alter table public.teams enable row level security;
alter table public.team_members enable row level security;
alter table public.team_competitions enable row level security;
alter table public.team_competition_teams enable row level security;
alter table public.team_meetings enable row level security;
alter table public.team_match_games enable row level security;

grant select,insert,update,delete on public.teams,public.team_members,public.team_competitions,public.team_competition_teams,public.team_meetings,public.team_match_games to authenticated;

drop policy if exists teams_owner_select on public.teams;
create policy teams_owner_select on public.teams for select to authenticated using(owner_id=(select auth.uid()) and public.can_use_teams());
drop policy if exists teams_owner_insert on public.teams;
create policy teams_owner_insert on public.teams for insert to authenticated with check(owner_id=(select auth.uid()) and public.can_use_teams());
drop policy if exists teams_owner_update on public.teams;
create policy teams_owner_update on public.teams for update to authenticated using(owner_id=(select auth.uid()) and public.can_use_teams()) with check(owner_id=(select auth.uid()) and public.can_use_teams());
drop policy if exists teams_owner_delete on public.teams;
create policy teams_owner_delete on public.teams for delete to authenticated using(owner_id=(select auth.uid()) and public.can_use_teams());

drop policy if exists team_members_owner_all on public.team_members;
create policy team_members_owner_all on public.team_members for all to authenticated
using(public.can_use_teams() and exists(select 1 from public.teams t where t.id=team_members.team_id and t.owner_id=(select auth.uid())))
with check(public.can_use_teams() and exists(select 1 from public.teams t where t.id=team_members.team_id and t.owner_id=(select auth.uid())));

drop policy if exists team_competitions_owner_select on public.team_competitions;
create policy team_competitions_owner_select on public.team_competitions for select to authenticated using(owner_id=(select auth.uid()) and public.can_use_teams());
drop policy if exists team_competitions_owner_insert on public.team_competitions;
create policy team_competitions_owner_insert on public.team_competitions for insert to authenticated with check(owner_id=(select auth.uid()) and public.can_use_teams());
drop policy if exists team_competitions_owner_update on public.team_competitions;
create policy team_competitions_owner_update on public.team_competitions for update to authenticated using(owner_id=(select auth.uid()) and public.can_use_teams()) with check(owner_id=(select auth.uid()) and public.can_use_teams());
drop policy if exists team_competitions_owner_delete on public.team_competitions;
create policy team_competitions_owner_delete on public.team_competitions for delete to authenticated using(owner_id=(select auth.uid()) and public.can_use_teams());

drop policy if exists team_competition_teams_owner_all on public.team_competition_teams;
create policy team_competition_teams_owner_all on public.team_competition_teams for all to authenticated
using(public.can_use_teams() and exists(select 1 from public.team_competitions c where c.id=team_competition_teams.competition_id and c.owner_id=(select auth.uid())))
with check(public.can_use_teams()
  and exists(select 1 from public.team_competitions c where c.id=team_competition_teams.competition_id and c.owner_id=(select auth.uid()))
  and exists(select 1 from public.teams t where t.id=team_competition_teams.team_id and t.owner_id=(select auth.uid())));

drop policy if exists team_meetings_owner_all on public.team_meetings;
create policy team_meetings_owner_all on public.team_meetings for all to authenticated
using(public.can_use_teams() and exists(select 1 from public.team_competitions c where c.id=team_meetings.competition_id and c.owner_id=(select auth.uid())))
with check(public.can_use_teams()
  and exists(select 1 from public.team_competitions c where c.id=team_meetings.competition_id and c.owner_id=(select auth.uid()))
  and exists(select 1 from public.team_competition_teams ct where ct.competition_id=team_meetings.competition_id and ct.team_id=team_meetings.home_team_id)
  and exists(select 1 from public.team_competition_teams ct where ct.competition_id=team_meetings.competition_id and ct.team_id=team_meetings.away_team_id));

drop policy if exists team_match_games_owner_all on public.team_match_games;
create policy team_match_games_owner_all on public.team_match_games for all to authenticated
using(public.can_use_teams() and exists(select 1 from public.team_meetings m join public.team_competitions c on c.id=m.competition_id where m.id=team_match_games.meeting_id and c.owner_id=(select auth.uid())))
with check(public.can_use_teams() and exists(select 1 from public.team_meetings m join public.team_competitions c on c.id=m.competition_id where m.id=team_match_games.meeting_id and c.owner_id=(select auth.uid())));
