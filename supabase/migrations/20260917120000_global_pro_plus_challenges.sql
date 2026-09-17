-- Connect Sports Pro — Global PRO+ challenges, season 2026 pilot
-- Challenges are sport-independent, require an explicit join and count only
-- verified CSP activity recorded after the player joins.

create table if not exists public.challenge_seasons (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  season_year smallint not null,
  name text not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  reward_cutoff timestamptz not null,
  required_completions integer not null default 20,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint challenge_seasons_dates_valid check (ends_at > starts_at),
  constraint challenge_seasons_reward_cutoff_valid check (reward_cutoff <= ends_at),
  constraint challenge_seasons_required_positive check (required_completions > 0)
);

create table if not exists public.challenges (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.challenge_seasons(id) on delete cascade,
  code text not null,
  title text not null,
  description text not null,
  rarity text not null,
  medal text not null,
  metric_key text not null,
  target_value integer not null,
  unit_label text not null,
  badge_symbol text not null,
  badge_label text not null,
  sort_order integer not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  join_deadline timestamptz not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint challenges_season_code_unique unique (season_id, code),
  constraint challenges_rarity_valid check (rarity in ('common','rare','elite')),
  constraint challenges_medal_valid check (medal in ('silver','gold','platinum')),
  constraint challenges_metric_valid check (metric_key in (
    'activity_count','active_days','training_count','match_count',
    'win_count','minutes','consecutive_days','active_weeks'
  )),
  constraint challenges_target_positive check (target_value > 0),
  constraint challenges_dates_valid check (ends_at > starts_at),
  constraint challenges_join_deadline_valid check (join_deadline between starts_at and ends_at)
);

create table if not exists public.player_challenges (
  user_id uuid not null references public.profiles(id) on delete cascade,
  challenge_id uuid not null references public.challenges(id) on delete cascade,
  joined_at timestamptz not null default now(),
  progress_value integer not null default 0,
  completed_at timestamptz,
  badge_awarded_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, challenge_id),
  constraint player_challenges_progress_nonnegative check (progress_value >= 0)
);

comment on table public.challenge_seasons is
  'Bounded annual CSP challenge seasons and their physical reward cutoff.';
comment on table public.challenges is
  'Global sport-independent PRO+ challenges with silver, gold and platinum badge tiers.';
comment on table public.player_challenges is
  'Owner-only manual challenge joins, calculated progress and awarded challenge badges.';

create index if not exists challenges_season_sort_idx
  on public.challenges(season_id, active, sort_order);
create index if not exists player_challenges_user_status_idx
  on public.player_challenges(user_id, completed_at, updated_at desc);
create index if not exists training_sessions_challenge_progress_idx
  on public.training_sessions(owner_id, status, completed_at desc);
create index if not exists tournament_players_challenge_user_idx
  on public.tournament_players(user_id, id);
create index if not exists league_players_challenge_user_idx
  on public.league_players(user_id, id);

alter table public.challenge_seasons enable row level security;
alter table public.challenges enable row level security;
alter table public.player_challenges enable row level security;

revoke all on table public.challenge_seasons from public, anon;
revoke all on table public.challenges from public, anon;
revoke all on table public.player_challenges from public, anon;
grant select on table public.challenge_seasons to authenticated, service_role;
grant select on table public.challenges to authenticated, service_role;
grant select, insert, update on table public.player_challenges to authenticated, service_role;

drop policy if exists challenge_seasons_pro_plus_select on public.challenge_seasons;
create policy challenge_seasons_pro_plus_select
on public.challenge_seasons for select to authenticated
using (
  active
  and public.has_plan_at_least((select auth.uid()), 'pro_plus')
);

drop policy if exists challenges_pro_plus_select on public.challenges;
create policy challenges_pro_plus_select
on public.challenges for select to authenticated
using (
  active
  and public.has_plan_at_least((select auth.uid()), 'pro_plus')
  and exists (
    select 1 from public.challenge_seasons s
    where s.id = season_id and s.active
  )
);

drop policy if exists player_challenges_owner_select on public.player_challenges;
create policy player_challenges_owner_select
on public.player_challenges for select to authenticated
using (
  user_id = (select auth.uid())
  and public.has_plan_at_least((select auth.uid()), 'pro_plus')
);

drop policy if exists player_challenges_owner_insert on public.player_challenges;
create policy player_challenges_owner_insert
on public.player_challenges for insert to authenticated
with check (
  user_id = (select auth.uid())
  and public.has_plan_at_least((select auth.uid()), 'pro_plus')
);

drop policy if exists player_challenges_owner_update on public.player_challenges;
create policy player_challenges_owner_update
on public.player_challenges for update to authenticated
using (
  user_id = (select auth.uid())
  and public.has_plan_at_least((select auth.uid()), 'pro_plus')
)
with check (
  user_id = (select auth.uid())
  and public.has_plan_at_least((select auth.uid()), 'pro_plus')
);

insert into public.challenge_seasons(
  slug, season_year, name, starts_at, ends_at, reward_cutoff, required_completions, active
)
values (
  'global-2026-pilot', 2026, 'CSP Global Challenges 2026',
  '2026-09-17 00:00:00 Europe/Bratislava',
  '2026-12-01 23:59:59 Europe/Bratislava',
  '2026-12-01 23:59:59 Europe/Bratislava',
  20, true
)
on conflict (slug) do update set
  season_year = excluded.season_year,
  name = excluded.name,
  starts_at = excluded.starts_at,
  ends_at = excluded.ends_at,
  reward_cutoff = excluded.reward_cutoff,
  required_completions = excluded.required_completions,
  active = true,
  updated_at = now();

insert into public.challenges(
  season_id, code, title, description, rarity, medal, metric_key,
  target_value, unit_label, badge_symbol, badge_label, sort_order,
  starts_at, ends_at, join_deadline, active
)
select s.id, seed.code, seed.title, seed.description, seed.rarity, seed.medal,
       seed.metric_key, seed.target_value, seed.unit_label, seed.badge_symbol,
       seed.badge_label, seed.sort_order, s.starts_at, s.ends_at, s.ends_at, true
from public.challenge_seasons s
cross join (values
  ('first_step','Prvý krok','Dokonči prvú overenú športovú aktivitu po pridaní sa k výzve.','common','silver','activity_count',1,'aktivita','1','FIRST STEP',1),
  ('three_of_seven','Tri zo siedmich','Buď aktívny počas troch rôznych dní.','common','silver','active_days',3,'dni','3/7','ACTIVE DAYS',2),
  ('five_activities','Rozbehnutá päťka','Dokonči päť overených športových aktivít.','common','silver','activity_count',5,'aktivít','5','ACTIVITIES',3),
  ('first_100_minutes','Prvých 100 minút','Nazbieraj sto minút overených športových aktivít.','common','silver','minutes',100,'min','100','MINUTES',4),
  ('training_three','Tréningová trojka','Dokonči tri tréningové jednotky v CSP.','common','silver','training_count',3,'tréningy','3','TRAININGS',5),
  ('matches_five','Päť zápasov','Odohraj päť oficiálnych turnajových alebo ligových zápasov.','common','silver','match_count',5,'zápasov','5','MATCHES',6),
  ('wins_three','Tri víťazstvá','Vyhraj tri oficiálne zápasy bez ohľadu na šport.','common','silver','win_count',3,'výhry','3W','WINS',7),
  ('active_days_ten','Desať aktívnych dní','Buď aktívny počas desiatich rôznych dní.','rare','gold','active_days',10,'dní','10D','ACTIVE DAYS',8),
  ('trainings_ten','Desať tréningov','Dokonči desať tréningových jednotiek.','rare','gold','training_count',10,'tréningov','10T','TRAININGS',9),
  ('matches_fifteen','Pätnásť zápasov','Odohraj pätnásť oficiálnych zápasov.','rare','gold','match_count',15,'zápasov','15M','MATCHES',10),
  ('wins_ten','Desať víťazstiev','Vyhraj desať oficiálnych zápasov.','rare','gold','win_count',10,'výhier','10W','WINS',11),
  ('ten_hours','Desaťhodinová výzva','Nazbieraj 600 minút overených športových aktivít.','rare','gold','minutes',600,'min','10H','ACTIVE TIME',12),
  ('three_day_streak','Tri dni v rade','Zaznamenaj aktivitu počas troch po sebe idúcich dní.','rare','gold','consecutive_days',3,'dni v rade','3×','STREAK',13),
  ('four_active_weeks','Štyri aktívne týždne','Zaznamenaj aspoň jednu aktivitu v štyroch rôznych týždňoch.','rare','gold','active_weeks',4,'týždne','4W','ACTIVE WEEKS',14),
  ('activities_thirty','Aktívna tridsiatka','Dokonči tridsať overených športových aktivít.','rare','gold','activity_count',30,'aktivít','30','ACTIVITIES',15),
  ('active_days_twenty','Dvadsať aktívnych dní','Buď aktívny počas dvadsiatich rôznych dní.','elite','platinum','active_days',20,'dní','20D','ACTIVE DAYS',16),
  ('trainings_twenty','Tréningová dvadsiatka','Dokonči dvadsať tréningových jednotiek.','elite','platinum','training_count',20,'tréningov','20T','TRAININGS',17),
  ('matches_thirty','Tridsať zápasov','Odohraj tridsať oficiálnych zápasov.','elite','platinum','match_count',30,'zápasov','30M','MATCHES',18),
  ('wins_twenty','Dvadsať víťazstiev','Vyhraj dvadsať oficiálnych zápasov.','elite','platinum','win_count',20,'výhier','20W','WINS',19),
  ('grand_thousand','Veľká tisícka','Nazbieraj tisíc minút overených športových aktivít.','elite','platinum','minutes',1000,'min','1K','MINUTES',20)
) as seed(code,title,description,rarity,medal,metric_key,target_value,unit_label,badge_symbol,badge_label,sort_order)
where s.slug = 'global-2026-pilot'
on conflict (season_id, code) do update set
  title = excluded.title,
  description = excluded.description,
  rarity = excluded.rarity,
  medal = excluded.medal,
  metric_key = excluded.metric_key,
  target_value = excluded.target_value,
  unit_label = excluded.unit_label,
  badge_symbol = excluded.badge_symbol,
  badge_label = excluded.badge_label,
  sort_order = excluded.sort_order,
  starts_at = excluded.starts_at,
  ends_at = excluded.ends_at,
  join_deadline = excluded.join_deadline,
  active = true,
  updated_at = now();

create or replace function public.refresh_my_challenge_progress()
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  r record;
  v_from timestamptz;
  v_to timestamptz;
  v_activity_count integer;
  v_active_days integer;
  v_training_count integer;
  v_match_count integer;
  v_win_count integer;
  v_minutes integer;
  v_consecutive_days integer;
  v_active_weeks integer;
  v_value integer;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if not public.has_plan_at_least(v_uid, 'pro_plus') then
    raise exception 'PRO+ plan required' using errcode = '42501';
  end if;

  for r in
    select pc.challenge_id, pc.joined_at, pc.completed_at,
           c.metric_key, c.target_value, c.starts_at, c.ends_at
    from public.player_challenges pc
    join public.challenges c on c.id = pc.challenge_id and c.active
    join public.challenge_seasons s on s.id = c.season_id and s.active
    where pc.user_id = v_uid
  loop
    v_from := greatest(r.starts_at, r.joined_at);
    v_to := least(r.ends_at, now());

    with activity as (
      select 'training:' || ts.id::text as activity_key,
             coalesce(ts.completed_at, ts.archived_at, ts.played_at, ts.updated_at, ts.created_at) as occurred_at,
             greatest(coalesce(nullif(ts.duration_seconds,0), nullif(ts.elapsed_seconds,0), 0),0)::bigint as duration_seconds,
             true as is_training, false as is_match, false as is_win
      from public.training_sessions ts
      where ts.owner_id = v_uid
        and ts.status in ('completed','archived')
        and coalesce(ts.completed_at, ts.archived_at, ts.played_at, ts.updated_at, ts.created_at) between v_from and v_to
      union all
      select 'tournament:' || m.id::text,
             coalesce(m.completed_at, m.started_at, m.scheduled_at, m.updated_at, m.created_at),
             greatest(coalesce(m.match_clock_elapsed_seconds,0),0)::bigint,
             false, true, (m.winner_id = tp.id)
      from public.tournament_players tp
      join public.matches m on m.player1_id = tp.id or m.player2_id = tp.id
      where tp.user_id = v_uid
        and m.status in ('completed','forfeited')
        and coalesce(m.completed_at, m.started_at, m.scheduled_at, m.updated_at, m.created_at) between v_from and v_to
      union all
      select 'league:' || lm.id::text,
             coalesce(lm.completed_at, lm.scheduled_at, lm.updated_at, lm.created_at),
             0::bigint,
             false, true, (lm.winner_id = lp.id)
      from public.league_players lp
      join public.league_matches lm on lm.player1_id = lp.id or lm.player2_id = lp.id
      where lp.user_id = v_uid
        and lm.status in ('completed','forfeited')
        and coalesce(lm.completed_at, lm.scheduled_at, lm.updated_at, lm.created_at) between v_from and v_to
    ),
    activity_days as (
      select distinct (a.occurred_at at time zone 'Europe/Bratislava')::date as active_day
      from activity a
    ),
    streak_groups as (
      select active_day,
             active_day - row_number() over(order by active_day)::integer as streak_group
      from activity_days
    ),
    streaks as (
      select count(*)::integer as streak_length
      from streak_groups
      group by streak_group
    )
    select
      count(*)::integer,
      count(distinct (a.occurred_at at time zone 'Europe/Bratislava')::date)::integer,
      count(*) filter(where a.is_training)::integer,
      count(*) filter(where a.is_match)::integer,
      count(*) filter(where a.is_win)::integer,
      floor(coalesce(sum(a.duration_seconds),0) / 60.0)::integer,
      coalesce((select max(streak_length) from streaks),0)::integer,
      count(distinct date_trunc('week', a.occurred_at at time zone 'Europe/Bratislava'))::integer
    into v_activity_count, v_active_days, v_training_count, v_match_count,
         v_win_count, v_minutes, v_consecutive_days, v_active_weeks
    from activity a;

    v_value := case r.metric_key
      when 'activity_count' then v_activity_count
      when 'active_days' then v_active_days
      when 'training_count' then v_training_count
      when 'match_count' then v_match_count
      when 'win_count' then v_win_count
      when 'minutes' then v_minutes
      when 'consecutive_days' then v_consecutive_days
      when 'active_weeks' then v_active_weeks
      else 0
    end;

    update public.player_challenges pc
    set progress_value = greatest(v_value, pc.progress_value),
        completed_at = case
          when pc.completed_at is not null then pc.completed_at
          when v_value >= r.target_value then now()
          else null
        end,
        badge_awarded_at = case
          when pc.badge_awarded_at is not null then pc.badge_awarded_at
          when v_value >= r.target_value then now()
          else null
        end,
        updated_at = now()
    where pc.user_id = v_uid and pc.challenge_id = r.challenge_id;
  end loop;
end;
$$;

revoke all on function public.refresh_my_challenge_progress() from public, anon;
grant execute on function public.refresh_my_challenge_progress() to authenticated, service_role;

create or replace function public.join_my_challenge(p_challenge_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_challenge record;
  v_row public.player_challenges;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if not public.has_plan_at_least(v_uid, 'pro_plus') then
    raise exception 'PRO+ plan required' using errcode = '42501';
  end if;

  select c.id, c.starts_at, c.ends_at, c.join_deadline
  into v_challenge
  from public.challenges c
  join public.challenge_seasons s on s.id = c.season_id
  where c.id = p_challenge_id and c.active and s.active;

  if not found then
    raise exception 'challenge not found' using errcode = 'P0002';
  end if;
  if now() < v_challenge.starts_at then
    raise exception 'challenge has not started' using errcode = '22023';
  end if;
  if now() > least(v_challenge.ends_at, v_challenge.join_deadline) then
    raise exception 'challenge entry is closed' using errcode = '22023';
  end if;

  insert into public.player_challenges(user_id, challenge_id, joined_at)
  values (v_uid, p_challenge_id, now())
  on conflict (user_id, challenge_id) do nothing;

  perform public.refresh_my_challenge_progress();

  select * into v_row
  from public.player_challenges
  where user_id = v_uid and challenge_id = p_challenge_id;

  return jsonb_build_object(
    'challenge_id', v_row.challenge_id,
    'joined_at', v_row.joined_at,
    'progress_value', v_row.progress_value,
    'completed_at', v_row.completed_at,
    'badge_awarded_at', v_row.badge_awarded_at
  );
end;
$$;

revoke all on function public.join_my_challenge(uuid) from public, anon;
grant execute on function public.join_my_challenge(uuid) to authenticated, service_role;

create or replace function public.get_my_challenges()
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_season public.challenge_seasons;
  v_payload jsonb;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;
  if not public.has_plan_at_least(v_uid, 'pro_plus') then
    raise exception 'PRO+ plan required' using errcode = '42501';
  end if;

  perform public.refresh_my_challenge_progress();

  select * into v_season
  from public.challenge_seasons s
  where s.active
  order by
    case when now() between s.starts_at and s.ends_at then 0
         when now() < s.starts_at then 1 else 2 end,
    s.starts_at
  limit 1;

  if v_season.id is null then
    return jsonb_build_object(
      'season', null,
      'summary', jsonb_build_object('total',0,'joined',0,'active',0,'completed',0,'completion_percent',0,'perfect_season',false),
      'items', '[]'::jsonb
    );
  end if;

  with item_rows as (
    select c.*,
           pc.joined_at, pc.progress_value, pc.completed_at, pc.badge_awarded_at,
           case
             when pc.completed_at is not null then 'completed'
             when pc.joined_at is not null then 'joined'
             when now() < c.starts_at then 'upcoming'
             when now() > least(c.ends_at,c.join_deadline) then 'closed'
             else 'available'
           end as player_state
    from public.challenges c
    left join public.player_challenges pc
      on pc.challenge_id = c.id and pc.user_id = v_uid
    where c.season_id = v_season.id and c.active
  ),
  summary as (
    select count(*)::integer as total,
           count(joined_at)::integer as joined,
           count(*) filter(where joined_at is not null and completed_at is null)::integer as active,
           count(completed_at)::integer as completed
    from item_rows
  )
  select jsonb_build_object(
    'season', jsonb_build_object(
      'id', v_season.id,
      'slug', v_season.slug,
      'year', v_season.season_year,
      'name', v_season.name,
      'starts_at', v_season.starts_at,
      'ends_at', v_season.ends_at,
      'reward_cutoff', v_season.reward_cutoff,
      'required_completions', v_season.required_completions
    ),
    'summary', jsonb_build_object(
      'total', sm.total,
      'joined', sm.joined,
      'active', sm.active,
      'completed', sm.completed,
      'completion_percent', case when sm.total = 0 then 0 else round(sm.completed::numeric * 100 / sm.total) end,
      'perfect_season', sm.completed >= v_season.required_completions,
      'remaining', greatest(v_season.required_completions - sm.completed, 0)
    ),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', i.id,
        'code', i.code,
        'title', i.title,
        'description', i.description,
        'rarity', i.rarity,
        'medal', i.medal,
        'metric_key', i.metric_key,
        'target_value', i.target_value,
        'unit_label', i.unit_label,
        'badge_symbol', i.badge_symbol,
        'badge_label', i.badge_label,
        'starts_at', i.starts_at,
        'ends_at', i.ends_at,
        'join_deadline', i.join_deadline,
        'joined_at', i.joined_at,
        'progress_value', coalesce(i.progress_value,0),
        'completed_at', i.completed_at,
        'badge_awarded_at', i.badge_awarded_at,
        'state', i.player_state,
        'progress_percent', least(100,round(coalesce(i.progress_value,0)::numeric * 100 / i.target_value)),
        'days_remaining', greatest(ceil(extract(epoch from (i.ends_at-now())) / 86400),0)
      ) order by i.sort_order)
      from item_rows i
    ), '[]'::jsonb)
  ) into v_payload
  from summary sm;

  return v_payload;
end;
$$;

comment on function public.get_my_challenges() is
  'Returns the signed-in PRO+ player challenge season, progress and awarded badges.';
comment on function public.join_my_challenge(uuid) is
  'Explicitly joins the signed-in PRO+ player to one global challenge.';

revoke all on function public.get_my_challenges() from public, anon;
grant execute on function public.get_my_challenges() to authenticated, service_role;

alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check check (notification_type = any (array[
  'new_follower','profile_respect',
  'club_membership_request','club_membership_invite','club_membership_approved','club_membership_rejected','club_membership_cancelled','club_membership_left','club_membership_removed',
  'federation_registration_request','federation_registration_invite','federation_registration_approved','federation_registration_rejected','federation_registration_cancelled','federation_registration_left','federation_registration_removed',
  'followed_player_training','followed_player_match','followed_player_tournament_result','followed_entity_event','followed_entity_tournament',
  'ihs_welcome','followed_event_series_round_result','achievement_unlocked','challenge_completed'
]::text[]));

create or replace function private.notify_challenge_completed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_challenge record;
begin
  if old.completed_at is not null or new.completed_at is null then
    return new;
  end if;

  select title, medal, code into v_challenge
  from public.challenges
  where id = new.challenge_id;

  if found then
    insert into public.notifications(
      recipient_id, actor_id, notification_type, entity_type, entity_id,
      title, body, action_url
    ) values (
      new.user_id, null, 'challenge_completed', 'challenge', new.challenge_id,
      'Výzva splnená: ' || v_challenge.title,
      initcap(v_challenge.medal) || ' · nový odznak bol pridaný do profilu.',
      '/profil-pro-plus/vyzvy/?challenge=' || v_challenge.code
    );
  end if;
  return new;
end;
$$;

revoke all on function private.notify_challenge_completed() from public, anon, authenticated;

drop trigger if exists trg_notify_challenge_completed on public.player_challenges;
create trigger trg_notify_challenge_completed
after update of completed_at on public.player_challenges
for each row execute function private.notify_challenge_completed();

