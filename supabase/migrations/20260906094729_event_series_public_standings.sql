begin;

-- CSP series standings v1
-- Public, read-only standings calculated from completed tournament results.
-- Default scoring: Kanianka 200 / 150 / 120 / 100 / 70 / 50 / 30.

create or replace function public.event_series_ranking_config_is_valid(
  p_config jsonb,
  p_total_rounds smallint
)
returns boolean
language plpgsql
immutable
parallel safe
set search_path = ''
as $$
declare
  v_rule jsonb;
  v_rule_count integer := 0;
  v_expected_min integer := 1;
  v_min integer;
  v_max integer;
  v_min_text text;
  v_max_text text;
  v_points_text text;
  v_best_text text;
  v_attendance_text text;
  v_open_ended_seen boolean := false;
begin
  if p_config is null or jsonb_typeof(p_config) <> 'object' then
    return false;
  end if;

  if coalesce(p_config ->> 'method', '') <> 'placement_points' then
    return false;
  end if;

  if jsonb_typeof(p_config -> 'points') <> 'array'
     or jsonb_array_length(p_config -> 'points') = 0 then
    return false;
  end if;

  v_best_text := p_config ->> 'best_results_count';
  if v_best_text is not null then
    if v_best_text !~ '^[1-9][0-9]*$'
       or v_best_text::integer > p_total_rounds then
      return false;
    end if;
  end if;

  v_attendance_text := coalesce(p_config ->> 'attendance_bonus', '0');
  if v_attendance_text !~ '^[0-9]+$'
     or v_attendance_text::integer <> 0 then
    return false;
  end if;

  for v_rule in
    select item.value
    from jsonb_array_elements(p_config -> 'points') with ordinality as item(value, position)
    order by item.position
  loop
    if v_open_ended_seen or jsonb_typeof(v_rule) <> 'object' then
      return false;
    end if;

    v_rule_count := v_rule_count + 1;
    v_min_text := v_rule ->> 'min_position';
    v_max_text := v_rule ->> 'max_position';
    v_points_text := v_rule ->> 'points';

    if v_min_text is null or v_min_text !~ '^[1-9][0-9]*$'
       or v_points_text is null or v_points_text !~ '^[0-9]+$' then
      return false;
    end if;

    v_min := v_min_text::integer;
    if v_min <> v_expected_min then
      return false;
    end if;

    if v_max_text is null then
      v_open_ended_seen := true;
    else
      if v_max_text !~ '^[1-9][0-9]*$' then
        return false;
      end if;

      v_max := v_max_text::integer;
      if v_max < v_min then
        return false;
      end if;
      v_expected_min := v_max + 1;
    end if;
  end loop;

  return v_rule_count > 0 and v_open_ended_seen;
exception
  when others then
    return false;
end;
$$;

revoke all on function public.event_series_ranking_config_is_valid(jsonb, smallint) from public;
grant execute on function public.event_series_ranking_config_is_valid(jsonb, smallint)
  to anon, authenticated, service_role;

alter table public.event_series
  alter column ranking_config set default
  '{"version":1,"preset":"kanianka_200","method":"placement_points","best_results_count":null,"attendance_bonus":0,"points":[{"min_position":1,"max_position":1,"points":200},{"min_position":2,"max_position":2,"points":150},{"min_position":3,"max_position":3,"points":120},{"min_position":4,"max_position":4,"points":100},{"min_position":5,"max_position":8,"points":70},{"min_position":9,"max_position":16,"points":50},{"min_position":17,"max_position":null,"points":30}],"tie_breakers":["victories","runner_up_finishes","third_places","best_position","match_wins"]}'::jsonb;

update public.event_series
set ranking_config =
  '{"version":1,"preset":"kanianka_200","method":"placement_points","best_results_count":null,"attendance_bonus":0,"points":[{"min_position":1,"max_position":1,"points":200},{"min_position":2,"max_position":2,"points":150},{"min_position":3,"max_position":3,"points":120},{"min_position":4,"max_position":4,"points":100},{"min_position":5,"max_position":8,"points":70},{"min_position":9,"max_position":16,"points":50},{"min_position":17,"max_position":null,"points":30}],"tie_breakers":["victories","runner_up_finishes","third_places","best_position","match_wins"]}'::jsonb
where ranking_config is null
   or jsonb_typeof(ranking_config) <> 'object'
   or case
        when jsonb_typeof(ranking_config -> 'points') = 'array'
          then jsonb_array_length(ranking_config -> 'points') = 0
        else true
      end;

alter table public.event_series
  drop constraint if exists event_series_ranking_config_valid_check;

alter table public.event_series
  add constraint event_series_ranking_config_valid_check
  check (public.event_series_ranking_config_is_valid(ranking_config, total_rounds));

comment on column public.event_series.ranking_config is
  'Immutable after the first completed series round for normal users. Defines placement points and optional best_results_count. attendance_bonus is fixed to 0 in v1.';

create or replace function public.event_series_points_for_position(
  p_config jsonb,
  p_final_position integer
)
returns integer
language plpgsql
immutable
parallel safe
set search_path = ''
as $$
declare
  v_rule jsonb;
  v_min integer;
  v_max integer;
begin
  if p_final_position is null or p_final_position < 1 then
    return 0;
  end if;

  for v_rule in
    select item.value
    from jsonb_array_elements(p_config -> 'points') with ordinality as item(value, position)
    order by item.position
  loop
    v_min := (v_rule ->> 'min_position')::integer;
    v_max := nullif(v_rule ->> 'max_position', '')::integer;

    if p_final_position >= v_min
       and (v_max is null or p_final_position <= v_max) then
      return (v_rule ->> 'points')::integer;
    end if;
  end loop;

  return 0;
exception
  when others then
    return 0;
end;
$$;

revoke all on function public.event_series_points_for_position(jsonb, integer) from public;
grant execute on function public.event_series_points_for_position(jsonb, integer)
  to anon, authenticated, service_role;

create table public.event_series_follows (
  series_id uuid not null references public.event_series(id) on delete cascade,
  follower_id uuid not null references public.profiles(id) on delete cascade,
  notify_round_results boolean not null default true,
  notify_upcoming boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (series_id, follower_id)
);

comment on table public.event_series_follows is
  'Users following a public event series. Preferences are reserved for result and upcoming-round notifications.';

create index event_series_follows_follower_idx
  on public.event_series_follows (follower_id, created_at desc);

drop trigger if exists event_series_follows_set_updated_at on public.event_series_follows;
create trigger event_series_follows_set_updated_at
before update on public.event_series_follows
for each row execute function public.set_updated_at();

alter table public.event_series_follows enable row level security;

drop policy if exists event_series_follows_public_select on public.event_series_follows;
create policy event_series_follows_public_select
on public.event_series_follows
for select
to anon, authenticated
using (
  exists (
    select 1
    from public.event_series s
    where s.id = event_series_follows.series_id
      and s.visibility = 'public'
      and s.status in ('published', 'completed')
  )
);

drop policy if exists event_series_follows_insert_own on public.event_series_follows;
create policy event_series_follows_insert_own
on public.event_series_follows
for insert
to authenticated
with check (
  (select auth.uid()) is not null
  and follower_id = (select auth.uid())
  and exists (
    select 1
    from public.event_series s
    where s.id = event_series_follows.series_id
      and s.visibility = 'public'
      and s.status in ('published', 'completed')
  )
);

drop policy if exists event_series_follows_update_own on public.event_series_follows;
create policy event_series_follows_update_own
on public.event_series_follows
for update
to authenticated
using (follower_id = (select auth.uid()))
with check (
  follower_id = (select auth.uid())
  and exists (
    select 1
    from public.event_series s
    where s.id = event_series_follows.series_id
      and s.visibility = 'public'
      and s.status in ('published', 'completed')
  )
);

drop policy if exists event_series_follows_delete_own on public.event_series_follows;
create policy event_series_follows_delete_own
on public.event_series_follows
for delete
to authenticated
using (follower_id = (select auth.uid()));

revoke all on table public.event_series_follows from anon, authenticated;
grant select on table public.event_series_follows to anon, authenticated;
grant insert, update, delete on table public.event_series_follows to authenticated;
grant all on table public.event_series_follows to service_role;

alter table public.social_reactions
  drop constraint if exists social_reactions_entity_type_check;

alter table public.social_reactions
  add constraint social_reactions_entity_type_check
  check (
    entity_type in (
      'profile', 'article', 'event', 'tournament', 'league',
      'training_session', 'gallery_collection', 'gallery_image', 'event_series'
    )
  );

drop policy if exists social_reactions_event_series_target_check on public.social_reactions;
create policy social_reactions_event_series_target_check
on public.social_reactions
as restrictive
for insert
to authenticated
with check (
  entity_type <> 'event_series'
  or exists (
    select 1
    from public.event_series s
    where s.id = social_reactions.entity_id
      and s.visibility = 'public'
      and s.status in ('published', 'completed')
  )
);

drop policy if exists event_series_public_select on public.event_series;
create policy event_series_public_select
on public.event_series
for select
to anon
using (status in ('published', 'completed') and visibility = 'public');

drop policy if exists event_series_authenticated_select on public.event_series;
create policy event_series_authenticated_select
on public.event_series
for select
to authenticated
using (
  owner_id = (select auth.uid())
  or (status in ('published', 'completed') and visibility = 'public')
);

create or replace function private.lock_event_series_ranking_config()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.ranking_config is distinct from old.ranking_config
     and (select auth.uid()) is not null
     and not coalesce(public.is_admin((select auth.uid())), false)
     and exists (
       select 1
       from public.events e
       join public.tournaments t on t.source_event_id = e.id
       where e.series_id = old.id
         and t.status in ('completed', 'archived')
     ) then
    raise exception 'SERIES_SCORING_LOCKED_AFTER_FIRST_COMPLETED_ROUND';
  end if;

  return new;
end;
$$;

revoke all on function private.lock_event_series_ranking_config() from public, anon, authenticated;

drop trigger if exists event_series_lock_ranking_config on public.event_series;
create trigger event_series_lock_ranking_config
before update of ranking_config on public.event_series
for each row execute function private.lock_event_series_ranking_config();

create or replace function private.validate_series_tournament_completion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_series_id uuid;
  v_player_count integer;
  v_positioned_count integer;
  v_identity_count integer;
begin
  if new.status <> 'completed' then
    return new;
  end if;

  select e.series_id
  into v_series_id
  from public.events e
  where e.id = new.source_event_id;

  if v_series_id is null then
    return new;
  end if;

  select
    count(tp.id)::integer,
    count(tr.id) filter (where tr.final_position is not null)::integer,
    count(tp.player_identity_id)::integer
  into v_player_count, v_positioned_count, v_identity_count
  from public.tournament_players tp
  left join public.tournament_results tr
    on tr.tournament_id = new.id
   and tr.tournament_player_id = tp.id
  where tp.tournament_id = new.id;

  if v_player_count < 2 then
    raise exception 'SERIES_TOURNAMENT_REQUIRES_AT_LEAST_TWO_PLAYERS';
  end if;

  if v_positioned_count <> v_player_count then
    raise exception 'SERIES_TOURNAMENT_REQUIRES_FINAL_POSITIONS_FOR_ALL_PLAYERS';
  end if;

  if v_identity_count <> v_player_count then
    raise exception 'SERIES_TOURNAMENT_REQUIRES_PLAYER_IDENTITIES';
  end if;

  return new;
end;
$$;

revoke all on function private.validate_series_tournament_completion() from public, anon, authenticated;

drop trigger if exists tournaments_validate_series_completion on public.tournaments;
create trigger tournaments_validate_series_completion
before update of status on public.tournaments
for each row execute function private.validate_series_tournament_completion();

alter table public.notifications
  drop constraint if exists notifications_type_check;

alter table public.notifications
  add constraint notifications_type_check
  check (
    notification_type in (
      'new_follower', 'profile_respect',
      'club_membership_request', 'club_membership_invite',
      'club_membership_approved', 'club_membership_rejected',
      'club_membership_cancelled', 'club_membership_left', 'club_membership_removed',
      'federation_registration_request', 'federation_registration_invite',
      'federation_registration_approved', 'federation_registration_rejected',
      'federation_registration_cancelled', 'federation_registration_left',
      'federation_registration_removed', 'followed_player_training',
      'followed_player_match', 'followed_player_tournament_result',
      'followed_entity_event', 'followed_entity_tournament', 'ihs_welcome',
      'followed_event_series_round_result'
    )
  );

create or replace function private.notify_event_series_round_completed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_series_id uuid;
  v_series_title text;
  v_round_number smallint;
begin
  if new.status <> 'completed' or old.status is not distinct from new.status then
    return new;
  end if;

  select s.id, s.title, e.series_round_number
  into v_series_id, v_series_title, v_round_number
  from public.events e
  join public.event_series s on s.id = e.series_id
  where e.id = new.source_event_id
    and s.visibility = 'public'
    and s.status in ('published', 'completed');

  if v_series_id is null then
    return new;
  end if;

  insert into public.notifications (
    recipient_id,
    actor_id,
    notification_type,
    entity_type,
    entity_id,
    title,
    body,
    action_url
  )
  select
    f.follower_id,
    new.owner_id,
    'followed_event_series_round_result',
    'event_series',
    v_series_id,
    'Aktualizované poradie série',
    format('%s. kolo série %s bolo ukončené.', v_round_number, v_series_title),
    '/seria/?id=' || v_series_id::text
  from public.event_series_follows f
  where f.series_id = v_series_id
    and f.notify_round_results
    and f.follower_id <> new.owner_id;

  return new;
end;
$$;

revoke all on function private.notify_event_series_round_completed() from public, anon, authenticated;

drop trigger if exists tournaments_notify_event_series_round_completed on public.tournaments;
create trigger tournaments_notify_event_series_round_completed
after update of status on public.tournaments
for each row execute function private.notify_event_series_round_completed();

create or replace view public.event_series_round_scores
with (security_invoker = true)
as
select
  s.id as series_id,
  s.title as series_title,
  s.total_rounds,
  nullif(s.ranking_config ->> 'best_results_count', '')::integer as best_results_count,
  e.id as event_id,
  e.title as event_title,
  e.series_round_number,
  e.starts_at as event_starts_at,
  t.id as tournament_id,
  t.completed_at as tournament_completed_at,
  tr.id as tournament_result_id,
  tp.id as tournament_player_id,
  tp.player_identity_id,
  coalesce(tr.user_id, tp.user_id) as profile_id,
  tp.name as player_name,
  tr.final_position,
  public.event_series_points_for_position(s.ranking_config, tr.final_position) as points,
  tr.matches_played,
  tr.wins,
  tr.losses,
  tr.score_for,
  tr.score_against
from public.event_series s
join public.events e on e.series_id = s.id
join public.tournaments t on t.source_event_id = e.id
join public.tournament_results tr on tr.tournament_id = t.id
join public.tournament_players tp
  on tp.id = tr.tournament_player_id
 and tp.tournament_id = t.id
where s.visibility = 'public'
  and s.status in ('published', 'completed')
  and t.status in ('completed', 'archived')
  and tr.final_position is not null
  and tp.player_identity_id is not null;

comment on view public.event_series_round_scores is
  'One public score row per player and completed series round. Points are derived from the locked series ranking_config.';

create or replace view public.event_series_round_results
with (security_invoker = true)
as
with prioritized as (
  select
    r.*,
    row_number() over (
      partition by r.series_id, r.player_identity_id
      order by r.points desc, r.final_position asc, r.series_round_number asc
    ) as result_priority
  from public.event_series_round_scores r
)
select
  p.*,
  (
    p.best_results_count is null
    or p.result_priority <= p.best_results_count
  ) as is_counted
from prioritized p;

comment on view public.event_series_round_results is
  'Public round detail including whether each result belongs to the player''s best X counted results.';

create or replace view public.event_series_standings
with (security_invoker = true)
as
with aggregated as (
  select
    r.series_id,
    r.series_title,
    r.total_rounds,
    r.best_results_count,
    r.player_identity_id,
    (array_agg(r.profile_id order by r.series_round_number desc)
      filter (where r.profile_id is not null))[1] as profile_id,
    (array_agg(r.player_name order by r.series_round_number desc))[1] as player_name,
    count(*)::integer as rounds_played,
    count(*) filter (where r.is_counted)::integer as counted_rounds,
    coalesce(sum(r.points) filter (where r.is_counted), 0)::integer as total_points,
    count(*) filter (where r.is_counted and r.final_position = 1)::integer as victories,
    count(*) filter (where r.is_counted and r.final_position = 2)::integer as runner_up_finishes,
    count(*) filter (where r.is_counted and r.final_position = 3)::integer as third_places,
    min(r.final_position) filter (where r.is_counted)::integer as best_position,
    coalesce(sum(r.wins) filter (where r.is_counted), 0)::integer as match_wins,
    max(r.series_round_number)::smallint as latest_round_number,
    (array_agg(r.points order by r.series_round_number desc))[1]::integer as latest_round_points
  from public.event_series_round_results r
  group by
    r.series_id,
    r.series_title,
    r.total_rounds,
    r.best_results_count,
    r.player_identity_id
), ranked as (
  select
    a.*,
    dense_rank() over (
      partition by a.series_id
      order by
        a.total_points desc,
        a.victories desc,
        a.runner_up_finishes desc,
        a.third_places desc,
        a.best_position asc nulls last,
        a.match_wins desc
    )::integer as standing_position
  from aggregated a
)
select
  standing_position,
  series_id,
  series_title,
  total_rounds,
  best_results_count,
  player_identity_id,
  profile_id,
  player_name,
  total_points,
  rounds_played,
  counted_rounds,
  victories,
  runner_up_finishes,
  third_places,
  best_position,
  match_wins,
  latest_round_number,
  latest_round_points
from ranked;

comment on view public.event_series_standings is
  'Public read-only overall series standings. Ties use victories, second places, third places, best finish and match wins.';

create or replace view public.event_series_public_rounds
with (security_invoker = true)
as
select
  s.id as series_id,
  s.title as series_title,
  s.total_rounds,
  e.id as event_id,
  e.series_round_number,
  e.title as event_title,
  e.starts_at,
  e.registration_enabled,
  e.registration_deadline,
  e.max_participants,
  t.id as tournament_id,
  t.status as tournament_status,
  case
    when e.status = 'cancelled' then 'cancelled'
    when t.status in ('completed', 'archived') then 'completed'
    when t.status = 'active' then 'live'
    else 'scheduled'
  end as round_status,
  count(tr.id) filter (where tr.final_position is not null)::integer as result_count,
  (array_agg(tp.player_identity_id order by tp.name)
    filter (where tr.final_position = 1))[1] as winner_identity_id,
  (array_agg(tp.name order by tp.name)
    filter (where tr.final_position = 1))[1] as winner_name
from public.event_series s
join public.events e on e.series_id = s.id
left join public.tournaments t on t.source_event_id = e.id
left join public.tournament_results tr on tr.tournament_id = t.id
left join public.tournament_players tp
  on tp.id = tr.tournament_player_id
 and tp.tournament_id = t.id
where s.visibility = 'public'
  and s.status in ('published', 'completed')
group by
  s.id,
  s.title,
  s.total_rounds,
  e.id,
  e.series_round_number,
  e.title,
  e.starts_at,
  e.registration_enabled,
  e.registration_deadline,
  e.max_participants,
  e.status,
  t.id,
  t.status;

comment on view public.event_series_public_rounds is
  'Public list of all scheduled, live, cancelled and completed rounds for a series.';

create or replace view public.event_series_social_counts
with (security_invoker = true)
as
select
  s.id as series_id,
  (
    select count(*)
    from public.event_series_follows f
    where f.series_id = s.id
  )::integer as follower_count,
  (
    select count(*)
    from public.social_reactions r
    where r.entity_type = 'event_series'
      and r.entity_id = s.id
      and r.reaction_type = 'like'
  )::integer as like_count
from public.event_series s
where s.visibility = 'public'
  and s.status in ('published', 'completed');

comment on view public.event_series_social_counts is
  'Public aggregate counts for series follows and likes; no frontend writes are possible through this view.';

revoke all on table public.event_series_round_scores from anon, authenticated;
revoke all on table public.event_series_round_results from anon, authenticated;
revoke all on table public.event_series_standings from anon, authenticated;
revoke all on table public.event_series_public_rounds from anon, authenticated;
revoke all on table public.event_series_social_counts from anon, authenticated;

grant select on table public.event_series_round_scores to anon, authenticated, service_role;
grant select on table public.event_series_round_results to anon, authenticated, service_role;
grant select on table public.event_series_standings to anon, authenticated, service_role;
grant select on table public.event_series_public_rounds to anon, authenticated, service_role;
grant select on table public.event_series_social_counts to anon, authenticated, service_role;

commit;

