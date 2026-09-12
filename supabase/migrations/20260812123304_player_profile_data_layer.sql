-- Connect Sports Pro — player profile data layer
-- One profile reads its entitlement from profiles.plan and combines existing
-- scoreboard sessions with linked tournament matches. New tables only cover
-- data that the current schema does not model: chosen disciplines and planned
-- training sessions.

create table public.player_disciplines (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.profiles(id) on delete cascade,
  sport text not null check (length(btrim(sport)) between 1 and 80),
  discipline text not null check (length(btrim(discipline)) between 1 and 120),
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint player_disciplines_player_sport_discipline_key
    unique (player_id, sport, discipline)
);

comment on table public.player_disciplines is
  'Sports and disciplines selected for a unified CSP player profile. One row may be marked as the player''s primary discipline.';

create index player_disciplines_player_id_idx
  on public.player_disciplines (player_id);

create unique index player_disciplines_one_primary_idx
  on public.player_disciplines (player_id)
  where is_primary;

create trigger player_disciplines_set_updated_at
before update on public.player_disciplines
for each row execute function public.set_updated_at();

alter table public.player_disciplines enable row level security;

create policy player_disciplines_select
  on public.player_disciplines
  for select
  to anon, authenticated
  using (true);

create policy player_disciplines_insert_own
  on public.player_disciplines
  for insert
  to authenticated
  with check ((select auth.uid()) = player_id);

create policy player_disciplines_update_own
  on public.player_disciplines
  for update
  to authenticated
  using ((select auth.uid()) = player_id)
  with check ((select auth.uid()) = player_id);

create policy player_disciplines_delete_own
  on public.player_disciplines
  for delete
  to authenticated
  using ((select auth.uid()) = player_id);

grant select on public.player_disciplines to anon, authenticated;
grant insert, update, delete on public.player_disciplines to authenticated;


create table public.training_plans (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (length(btrim(title)) between 1 and 160),
  sport text not null check (length(btrim(sport)) between 1 and 80),
  discipline text not null check (length(btrim(discipline)) between 1 and 120),
  scheduled_for timestamptz not null,
  target_duration_minutes smallint
    check (target_duration_minutes is null or target_duration_minutes between 1 and 1440),
  venue text,
  notes text,
  status text not null default 'planned'
    check (status in ('planned', 'completed', 'missed', 'cancelled')),
  completed_session_id uuid unique
    references public.training_sessions(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.training_plans is
  'Player-owned training schedule used by the profile calendar. Completed plans may link to the scoreboard session that fulfilled them.';

create index training_plans_player_scheduled_idx
  on public.training_plans (player_id, scheduled_for desc);

create index training_plans_upcoming_idx
  on public.training_plans (player_id, scheduled_for)
  where status = 'planned';

create index training_plans_completed_session_id_idx
  on public.training_plans (completed_session_id)
  where completed_session_id is not null;

create trigger training_plans_set_updated_at
before update on public.training_plans
for each row execute function public.set_updated_at();

alter table public.training_plans enable row level security;

create policy training_plans_select_own
  on public.training_plans
  for select
  to authenticated
  using ((select auth.uid()) = player_id);

create policy training_plans_insert_own_pro
  on public.training_plans
  for insert
  to authenticated
  with check (
    (select auth.uid()) = player_id
    and (select public.has_feature_access((select auth.uid()), 'training_planner'))
  );

create policy training_plans_update_own_pro
  on public.training_plans
  for update
  to authenticated
  using (
    (select auth.uid()) = player_id
    and (select public.has_feature_access((select auth.uid()), 'training_planner'))
  )
  with check (
    (select auth.uid()) = player_id
    and (select public.has_feature_access((select auth.uid()), 'training_planner'))
  );

create policy training_plans_delete_own_pro
  on public.training_plans
  for delete
  to authenticated
  using (
    (select auth.uid()) = player_id
    and (select public.has_feature_access((select auth.uid()), 'training_planner'))
  );

grant select, insert, update, delete on public.training_plans to authenticated;


insert into public.feature_gates (feature_key, min_plan, description)
values
  ('profile_analytics', 'pro', 'Advanced performance analytics in the player profile.'),
  ('training_planner', 'pro', 'Schedule and manage planned training sessions in the profile calendar.')
on conflict (feature_key) do update
set min_plan = excluded.min_plan,
    description = excluded.description;


-- Seed the new discipline table from real scoreboard history. The most-used
-- discipline becomes primary; remaining historic disciplines stay available.
with ranked as (
  select
    owner_id,
    sport,
    discipline,
    row_number() over (
      partition by owner_id
      order by count(*) desc, max(played_at) desc, sport, discipline
    ) as position
  from public.training_sessions
  group by owner_id, sport, discipline
)
insert into public.player_disciplines (player_id, sport, discipline, is_primary)
select owner_id, sport, discipline, position = 1
from ranked
on conflict (player_id, sport, discipline) do nothing;


create function public.get_my_player_profile_dashboard()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with me as (
    select
      p.id,
      p.full_name,
      p.role::text as role,
      public.current_plan(p.id) as plan,
      p.avatar_url,
      p.cover_url,
      p.bio,
      p.created_at
    from public.profiles p
    where p.id = (select auth.uid())
  ),
  range_start as (
    select now() - interval '30 days' as at
  ),
  recent_training as (
    select ts.*
    from public.training_sessions ts, range_start r
    where ts.owner_id = (select id from me)
      and ts.status = 'completed'
      and coalesce(ts.completed_at, ts.played_at) >= r.at
  ),
  my_tournament_players as (
    select tp.id, tp.tournament_id
    from public.tournament_players tp
    where tp.user_id = (select id from me)
  ),
  recent_matches as (
    select
      m.id,
      m.tournament_id,
      t.name as tournament_name,
      t.sport,
      t.discipline,
      mine.id as my_player_id,
      opponent.name as opponent_name,
      case when m.player1_id = mine.id then m.score1 else m.score2 end as my_score,
      case when m.player1_id = mine.id then m.score2 else m.score1 end as opponent_score,
      case
        when m.winner_id = mine.id then 'win'
        when m.winner_id is null then 'unknown'
        else 'loss'
      end as result,
      m.match_clock_elapsed_seconds as duration_seconds,
      coalesce(m.completed_at, m.started_at, m.scheduled_at, m.created_at) as occurred_at
    from my_tournament_players mine
    join public.matches m
      on m.player1_id = mine.id or m.player2_id = mine.id
    join public.tournaments t on t.id = m.tournament_id
    left join public.tournament_players opponent
      on opponent.id = case when m.player1_id = mine.id then m.player2_id else m.player1_id end
    cross join range_start r
    where m.status in ('completed', 'forfeited')
      and coalesce(m.completed_at, m.started_at, m.scheduled_at, m.created_at) >= r.at
  ),
  training_summary as (
    select
      count(*)::integer as completed_count,
      coalesce(sum(coalesce(duration_seconds, elapsed_seconds, 0)), 0)::bigint as duration_seconds
    from recent_training
  ),
  match_summary as (
    select
      count(*)::integer as completed_count,
      count(*) filter (where result = 'win')::integer as wins,
      count(*) filter (where result = 'loss')::integer as losses,
      coalesce(sum(duration_seconds), 0)::bigint as duration_seconds
    from recent_matches
  ),
  plan_summary as (
    select
      count(*) filter (where status = 'planned')::integer as planned_count,
      count(*) filter (where status = 'missed')::integer as missed_count
    from public.training_plans tp, range_start r
    where tp.player_id = (select id from me)
      and tp.scheduled_for >= r.at
  )
  select jsonb_build_object(
    'profile', coalesce((select to_jsonb(me) from me), '{}'::jsonb),
    'disciplines', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', pd.id,
          'sport', pd.sport,
          'discipline', pd.discipline,
          'is_primary', pd.is_primary
        ) order by pd.is_primary desc, pd.sport, pd.discipline
      )
      from public.player_disciplines pd
      where pd.player_id = (select id from me)
    ), '[]'::jsonb),
    'summary', (
      select jsonb_build_object(
        'period_days', 30,
        'time_in_game_seconds', ts.duration_seconds + ms.duration_seconds,
        'trainings_completed', ts.completed_count,
        'trainings_planned', ps.planned_count,
        'trainings_missed', ps.missed_count,
        'matches_completed', ms.completed_count,
        'wins', ms.wins,
        'losses', ms.losses,
        'win_rate', case
          when ms.wins + ms.losses = 0 then 0
          else round(ms.wins::numeric * 100 / (ms.wins + ms.losses), 1)
        end,
        'analytics_unlocked', public.has_feature_access((select id from me), 'profile_analytics'),
        'training_planner_unlocked', public.has_feature_access((select id from me), 'training_planner')
      )
      from training_summary ts
      cross join match_summary ms
      cross join plan_summary ps
    ),
    'upcoming_trainings', coalesce((
      select jsonb_agg(to_jsonb(upcoming) order by upcoming.scheduled_for)
      from (
        select id, title, sport, discipline, scheduled_for,
               target_duration_minutes, venue, status
        from public.training_plans
        where player_id = (select id from me)
          and status = 'planned'
          and scheduled_for >= now()
        order by scheduled_for
        limit 10
      ) upcoming
    ), '[]'::jsonb),
    'recent_trainings', coalesce((
      select jsonb_agg(to_jsonb(history) order by history.occurred_at desc)
      from (
        select id, sport, discipline, player_names, final_score, winner_name,
               coalesce(duration_seconds, elapsed_seconds) as duration_seconds,
               coalesce(completed_at, played_at) as occurred_at
        from recent_training
        order by coalesce(completed_at, played_at) desc
        limit 20
      ) history
    ), '[]'::jsonb),
    'recent_matches', coalesce((
      select jsonb_agg(to_jsonb(history) order by history.occurred_at desc)
      from (
        select id, tournament_id, tournament_name, sport, discipline,
               opponent_name, my_score, opponent_score, result,
               duration_seconds, occurred_at
        from recent_matches
        order by occurred_at desc
        limit 20
      ) history
    ), '[]'::jsonb)
  );
$$;

comment on function public.get_my_player_profile_dashboard() is
  'Returns the signed-in player''s plan-aware 30-day profile dataset. Uses exact profile links for tournament results and owner-scoped scoreboard sessions for training history.';

revoke all on function public.get_my_player_profile_dashboard() from public, anon;
grant execute on function public.get_my_player_profile_dashboard() to authenticated, service_role;

