begin;

create table if not exists public.leagues (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete restrict,
  club_id uuid null references public.clubs(id) on delete set null,
  name text not null check (char_length(trim(name)) between 3 and 160),
  public_slug text unique,
  sport text not null,
  discipline text null,
  season_name text not null,
  description text null,
  rules_text text null,
  competition_format text not null default 'round_robin_single'
    check (competition_format in ('round_robin_single','round_robin_double','round_robin_playoff')),
  scheduling_mode text not null default 'rounds'
    check (scheduling_mode in ('rounds','open_deadline')),
  status text not null default 'draft'
    check (status in ('draft','registration','active','playoff','completed','archived')),
  visibility text not null default 'public'
    check (visibility in ('public','unlisted','private')),
  starts_on date null,
  ends_on date null,
  registration_deadline timestamptz null,
  max_players integer null check (max_players is null or max_players between 2 and 512),
  win_points numeric(8,2) not null default 3,
  draw_points numeric(8,2) not null default 1,
  loss_points numeric(8,2) not null default 0,
  forfeit_win_points numeric(8,2) not null default 3,
  forfeit_loss_points numeric(8,2) not null default 0,
  allow_draws boolean not null default false,
  require_opponent_confirmation boolean not null default true,
  tiebreak_order jsonb not null default '["head_to_head","score_difference","wins","score_for"]'::jsonb,
  playoff_size integer null check (playoff_size is null or playoff_size in (4,8,16,32)),
  config jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  published_at timestamptz null,
  completed_at timestamptz null
);

comment on table public.leagues is 'CSP individual leagues. Standings are computed from league_matches and never manually stored.';

create table if not exists public.league_admins (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'admin' check (role in ('owner','admin','scorer')),
  created_at timestamptz not null default now(),
  unique (league_id, user_id)
);

create table if not exists public.league_players (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  user_id uuid null references public.profiles(id) on delete set null,
  display_name text not null check (char_length(trim(display_name)) between 1 and 120),
  seed integer null check (seed is null or seed > 0),
  status text not null default 'active' check (status in ('invited','registered','active','withdrawn','disqualified')),
  joined_at timestamptz not null default now(),
  withdrawn_at timestamptz null,
  metadata jsonb not null default '{}'::jsonb,
  unique (league_id, user_id)
);

create unique index if not exists league_players_unique_guest_name
  on public.league_players (league_id, lower(display_name))
  where user_id is null;

create table if not exists public.league_rounds (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  round_number integer not null check (round_number > 0),
  name text null,
  starts_on date null,
  deadline_at timestamptz null,
  status text not null default 'scheduled' check (status in ('scheduled','open','closed','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (league_id, round_number)
);

create table if not exists public.league_matches (
  id uuid primary key default gen_random_uuid(),
  league_id uuid not null references public.leagues(id) on delete cascade,
  round_id uuid null references public.league_rounds(id) on delete set null,
  round_number integer not null check (round_number > 0),
  leg_number integer not null default 1 check (leg_number in (1,2)),
  match_number integer not null check (match_number > 0),
  player1_id uuid not null references public.league_players(id) on delete restrict,
  player2_id uuid not null references public.league_players(id) on delete restrict,
  scheduled_at timestamptz null,
  station_id uuid null references public.stations(id) on delete set null,
  location_text text null,
  status text not null default 'unscheduled'
    check (status in ('unscheduled','scheduled','live','pending_confirmation','completed','postponed','forfeited','cancelled','disputed')),
  score1 integer null check (score1 is null or score1 >= 0),
  score2 integer null check (score2 is null or score2 >= 0),
  winner_id uuid null references public.league_players(id) on delete restrict,
  result_type text null check (result_type is null or result_type in ('normal','draw','forfeit','walkover','admin')),
  reported_by uuid null references public.profiles(id) on delete set null,
  reported_at timestamptz null,
  confirmed_by uuid null references public.profiles(id) on delete set null,
  confirmed_at timestamptz null,
  dispute_note text null,
  organizer_note text null,
  completed_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (player1_id <> player2_id),
  check (winner_id is null or winner_id in (player1_id, player2_id)),
  unique (league_id, leg_number, round_number, match_number)
);

create index if not exists leagues_owner_idx on public.leagues(owner_id);
create index if not exists leagues_club_idx on public.leagues(club_id);
create index if not exists leagues_status_visibility_idx on public.leagues(status, visibility);
create index if not exists league_players_league_idx on public.league_players(league_id);
create index if not exists league_players_user_idx on public.league_players(user_id);
create index if not exists league_matches_league_status_idx on public.league_matches(league_id, status);
create index if not exists league_matches_players_idx on public.league_matches(player1_id, player2_id);
create index if not exists league_matches_schedule_idx on public.league_matches(scheduled_at);

create or replace function public.set_league_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_leagues_updated_at
before update on public.leagues
for each row execute function public.set_league_updated_at();

create trigger trg_league_rounds_updated_at
before update on public.league_rounds
for each row execute function public.set_league_updated_at();

create trigger trg_league_matches_updated_at
before update on public.league_matches
for each row execute function public.set_league_updated_at();

create or replace function public.can_manage_league(p_league_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.leagues l
    where l.id = p_league_id
      and (
        l.owner_id = auth.uid()
        or exists (
          select 1 from public.league_admins la
          where la.league_id = l.id
            and la.user_id = auth.uid()
            and la.role in ('owner','admin','scorer')
        )
        or exists (
          select 1 from public.profiles p
          where p.id = auth.uid() and p.is_admin = true
        )
      )
  );
$$;

grant execute on function public.can_manage_league(uuid) to anon, authenticated;

create or replace function public.generate_league_schedule(p_league_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_format text;
  v_players uuid[];
  v_count integer;
  v_slots uuid[];
  v_round integer;
  v_match integer;
  v_leg integer;
  v_i integer;
  v_p1 uuid;
  v_p2 uuid;
  v_round_id uuid;
  v_total integer := 0;
  v_tmp uuid;
begin
  if not public.can_manage_league(p_league_id) then
    raise exception 'Not authorized to generate this league schedule';
  end if;

  select competition_format into v_format
  from public.leagues where id = p_league_id for update;

  if v_format is null then raise exception 'League not found'; end if;

  select array_agg(id order by coalesce(seed, 2147483647), joined_at, id)
  into v_players
  from public.league_players
  where league_id = p_league_id and status in ('registered','active');

  v_count := coalesce(array_length(v_players,1),0);
  if v_count < 2 then raise exception 'At least 2 active players are required'; end if;

  delete from public.league_matches where league_id = p_league_id;
  delete from public.league_rounds where league_id = p_league_id;

  v_slots := v_players;
  if mod(v_count,2)=1 then
    v_slots := array_append(v_slots, null::uuid);
    v_count := v_count + 1;
  end if;

  for v_leg in 1..case when v_format='round_robin_double' then 2 else 1 end loop
    for v_round in 1..(v_count-1) loop
      insert into public.league_rounds(league_id, round_number, name)
      values (p_league_id, ((v_leg-1)*(v_count-1))+v_round,
              case when v_leg=1 then 'Kolo '||v_round else 'Odveta '||v_round end)
      returning id into v_round_id;

      v_match := 0;
      for v_i in 1..(v_count/2) loop
        v_p1 := v_slots[v_i];
        v_p2 := v_slots[v_count-v_i+1];
        if v_p1 is not null and v_p2 is not null then
          v_match := v_match + 1;
          if v_leg=2 then
            v_tmp := v_p1; v_p1 := v_p2; v_p2 := v_tmp;
          end if;
          insert into public.league_matches(
            league_id, round_id, round_number, leg_number, match_number, player1_id, player2_id
          ) values (
            p_league_id, v_round_id, ((v_leg-1)*(v_count-1))+v_round, v_leg, v_match, v_p1, v_p2
          );
          v_total := v_total + 1;
        end if;
      end loop;

      v_tmp := v_slots[v_count];
      for v_i in reverse v_count..3 loop
        v_slots[v_i] := v_slots[v_i-1];
      end loop;
      v_slots[2] := v_tmp;
    end loop;
  end loop;

  return jsonb_build_object('league_id',p_league_id,'players',array_length(v_players,1),'matches',v_total);
end;
$$;

grant execute on function public.generate_league_schedule(uuid) to authenticated;

create or replace function public.get_league_standings(p_league_id uuid)
returns table (
  standing_position bigint,
  league_player_id uuid,
  user_id uuid,
  display_name text,
  played bigint,
  wins bigint,
  draws bigint,
  losses bigint,
  score_for bigint,
  score_against bigint,
  score_difference bigint,
  points numeric,
  form text[]
)
language sql
stable
security definer
set search_path = public
as $$
with eligible as (
  select lp.id, lp.user_id, lp.display_name
  from public.league_players lp
  join public.leagues l on l.id=lp.league_id
  where lp.league_id=p_league_id
    and lp.status in ('registered','active','withdrawn')
    and (l.visibility in ('public','unlisted') or public.can_manage_league(l.id) or lp.user_id=auth.uid())
), results as (
  select m.*, l.win_points, l.draw_points, l.loss_points,
         l.forfeit_win_points, l.forfeit_loss_points
  from public.league_matches m
  join public.leagues l on l.id=m.league_id
  where m.league_id=p_league_id and m.status in ('completed','forfeited')
), per_player as (
  select e.id league_player_id, e.user_id, e.display_name,
    count(r.id) as played,
    count(*) filter (where r.winner_id=e.id) as wins,
    count(*) filter (where r.result_type='draw') as draws,
    count(*) filter (where r.result_type<>'draw' and r.winner_id is distinct from e.id) as losses,
    coalesce(sum(case when r.player1_id=e.id then r.score1 else r.score2 end),0)::bigint as score_for,
    coalesce(sum(case when r.player1_id=e.id then r.score2 else r.score1 end),0)::bigint as score_against,
    coalesce(sum(
      case
        when r.result_type='draw' then r.draw_points
        when r.winner_id=e.id and r.result_type in ('forfeit','walkover') then r.forfeit_win_points
        when r.winner_id=e.id then r.win_points
        when r.result_type in ('forfeit','walkover') then r.forfeit_loss_points
        else r.loss_points
      end
    ),0)::numeric as points
  from eligible e
  left join results r on e.id in (r.player1_id,r.player2_id)
  group by e.id,e.user_id,e.display_name
), recent_form as (
  select e.id,
    coalesce(array_agg(x.outcome order by x.completed_at desc) filter (where x.rn<=5),array[]::text[]) form
  from eligible e
  left join lateral (
    select m.completed_at,
      case when m.result_type='draw' then 'D' when m.winner_id=e.id then 'W' else 'L' end outcome,
      row_number() over(order by m.completed_at desc nulls last, m.updated_at desc) rn
    from results m where e.id in (m.player1_id,m.player2_id)
  ) x on true
  group by e.id
), ranked as (
 select p.*, (p.score_for-p.score_against)::bigint score_difference, f.form,
   row_number() over(order by p.points desc,(p.score_for-p.score_against) desc,p.wins desc,p.score_for desc,p.display_name asc) standing_position
 from per_player p join recent_form f on f.id=p.league_player_id
)
select standing_position,league_player_id,user_id,display_name,played,wins,draws,losses,
       score_for,score_against,score_difference,points,form
from ranked order by standing_position;
$$;

grant execute on function public.get_league_standings(uuid) to anon, authenticated;

alter table public.leagues enable row level security;
alter table public.league_admins enable row level security;
alter table public.league_players enable row level security;
alter table public.league_rounds enable row level security;
alter table public.league_matches enable row level security;

create policy leagues_public_read on public.leagues for select
using (visibility in ('public','unlisted') and status <> 'draft' or owner_id=auth.uid() or public.can_manage_league(id));
create policy leagues_owner_insert on public.leagues for insert to authenticated
with check (owner_id=auth.uid());
create policy leagues_manager_update on public.leagues for update to authenticated
using (public.can_manage_league(id)) with check (public.can_manage_league(id));
create policy leagues_manager_delete on public.leagues for delete to authenticated
using (public.can_manage_league(id));

create policy league_admins_read on public.league_admins for select to authenticated
using (public.can_manage_league(league_id) or user_id=auth.uid());
create policy league_admins_manage on public.league_admins for all to authenticated
using (public.can_manage_league(league_id)) with check (public.can_manage_league(league_id));

create policy league_players_public_read on public.league_players for select
using (exists(select 1 from public.leagues l where l.id=league_id and (l.visibility in ('public','unlisted') and l.status<>'draft' or public.can_manage_league(l.id) or user_id=auth.uid())));
create policy league_players_manage on public.league_players for all to authenticated
using (public.can_manage_league(league_id)) with check (public.can_manage_league(league_id));

create policy league_rounds_public_read on public.league_rounds for select
using (exists(select 1 from public.leagues l where l.id=league_id and (l.visibility in ('public','unlisted') and l.status<>'draft' or public.can_manage_league(l.id))));
create policy league_rounds_manage on public.league_rounds for all to authenticated
using (public.can_manage_league(league_id)) with check (public.can_manage_league(league_id));

create policy league_matches_public_read on public.league_matches for select
using (exists(select 1 from public.leagues l where l.id=league_id and (l.visibility in ('public','unlisted') and l.status<>'draft' or public.can_manage_league(l.id)))) ;
create policy league_matches_manage on public.league_matches for all to authenticated
using (public.can_manage_league(league_id)) with check (public.can_manage_league(league_id));

commit;
