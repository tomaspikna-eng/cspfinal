-- Connect Sports Pro — release security and performance hardening

create table if not exists public.translation_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  usage_date date not null default current_date,
  request_count integer not null default 0 check (request_count >= 0),
  character_count integer not null default 0 check (character_count >= 0),
  window_started_at timestamptz not null default clock_timestamp(),
  window_request_count integer not null default 0 check (window_request_count >= 0),
  updated_at timestamptz not null default clock_timestamp(),
  primary key (user_id, usage_date)
);

alter table public.translation_usage enable row level security;

drop policy if exists translation_usage_own_select on public.translation_usage;
create policy translation_usage_own_select
on public.translation_usage for select
to authenticated
using (user_id = (select auth.uid()));

revoke all on table public.translation_usage from public, anon, authenticated;
grant select on table public.translation_usage to authenticated;
grant all on table public.translation_usage to service_role;

create or replace function public.consume_translation_quota(p_character_count integer)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := clock_timestamp();
  v_usage public.translation_usage%rowtype;
  v_window_count integer;
  v_window_started_at timestamptz;
begin
  if v_user_id is null or p_character_count < 1 or p_character_count > 28000 then
    return false;
  end if;

  insert into public.translation_usage (user_id, usage_date)
  values (v_user_id, current_date)
  on conflict (user_id, usage_date) do nothing;

  select * into v_usage
  from public.translation_usage
  where user_id = v_user_id and usage_date = current_date
  for update;

  if v_usage.window_started_at <= v_now - interval '1 minute' then
    v_window_started_at := v_now;
    v_window_count := 0;
  else
    v_window_started_at := v_usage.window_started_at;
    v_window_count := v_usage.window_request_count;
  end if;

  if v_usage.request_count >= 200
     or v_usage.character_count + p_character_count > 100000
     or v_window_count >= 8 then
    return false;
  end if;

  update public.translation_usage
  set request_count = request_count + 1,
      character_count = character_count + p_character_count,
      window_started_at = v_window_started_at,
      window_request_count = v_window_count + 1,
      updated_at = v_now
  where user_id = v_user_id and usage_date = current_date;

  return true;
end;
$$;

revoke all on function public.consume_translation_quota(integer) from public, anon;
grant execute on function public.consume_translation_quota(integer) to authenticated, service_role;

drop policy if exists display_pairing_requests_no_direct_access on public.display_pairing_requests;
create policy display_pairing_requests_no_direct_access
on public.display_pairing_requests for select
to anon, authenticated
using (false);

alter function public.normalize_ihs_sport(text) set search_path = '';
alter function public.ihs_level_for_rating(numeric) set search_path = '';
alter function public.ihs_grade_for_level(text) set search_path = '';
alter function public.set_league_updated_at() set search_path = '';
alter function public.set_public_profile_updated_at() set search_path = '';

do $acl$
declare
  v_function record;
  v_signature text;
  v_anon_functions constant text[] := array[
    'complete_scoreboard_match',
    'confirm_station_player_presence',
    'get_card_display_payload',
    'get_display_pairing_status',
    'get_grouped_tournament_calendar',
    'get_ihs_player_directory',
    'get_league_standings',
    'get_public_event_calendar',
    'get_public_event_preregistrations',
    'get_public_ihs_grade',
    'get_scoreboard_event_actions',
    'get_scoreboard_match',
    'get_station_tablet_state',
    'get_tournament_display_screen_payload',
    'get_tournament_display_view',
    'global_search',
    'record_scoreboard_match_event',
    'request_display_pairing',
    'start_station_match',
    'submit_event_preregistration',
    'touch_tournament_display_screen',
    'undo_scoreboard_event',
    'update_scoreboard_match_live'
  ];
begin
  for v_function in
    select p.oid, p.proname, n.nspname
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
  loop
    v_signature := format('%I.%I(%s)', v_function.nspname, v_function.proname,
      pg_catalog.pg_get_function_identity_arguments(v_function.oid));
    execute format('revoke execute on function %s from public, anon', v_signature);
    execute format('grant execute on function %s to authenticated, service_role', v_signature);
    if v_function.proname = any(v_anon_functions) then
      execute format('grant execute on function %s to anon', v_signature);
    end if;
  end loop;
end;
$acl$;

create index if not exists audit_logs_user_id_idx on public.audit_logs(user_id);
create index if not exists calendar_station_blocks_event_id_idx on public.calendar_station_blocks(event_id);
create index if not exists calendar_station_blocks_tournament_id_idx on public.calendar_station_blocks(tournament_id);
create index if not exists club_manager_live_sessions_price_profile_id_idx on public.club_manager_live_sessions(price_profile_id);
create index if not exists club_representatives_club_id_idx on public.club_representatives(club_id);
create index if not exists club_representatives_owner_id_idx on public.club_representatives(owner_id);
create index if not exists gallery_images_uploader_id_idx on public.gallery_images(uploader_id);
create index if not exists league_admins_user_id_idx on public.league_admins(user_id);
create index if not exists league_matches_confirmed_by_idx on public.league_matches(confirmed_by);
create index if not exists league_matches_reported_by_idx on public.league_matches(reported_by);
create index if not exists league_matches_round_id_idx on public.league_matches(round_id);
create index if not exists league_matches_station_id_idx on public.league_matches(station_id);
create index if not exists league_matches_winner_id_idx on public.league_matches(winner_id);
create index if not exists matches_late_player_id_idx on public.matches(late_player_id);
create index if not exists matches_shot_clock_current_player_id_idx on public.matches(shot_clock_current_player_id);
create index if not exists matches_shot_clock_operator_id_idx on public.matches(shot_clock_operator_id);
create index if not exists notifications_actor_id_idx on public.notifications(actor_id);
create index if not exists phase_qualifiers_tournament_player_id_idx on public.phase_qualifiers(tournament_player_id);
create index if not exists player_identities_created_by_idx on public.player_identities(created_by);
create index if not exists player_identities_merged_into_id_idx on public.player_identities(merged_into_id);
create index if not exists reservation_blocks_created_by_idx on public.reservation_blocks(created_by);
create index if not exists reservation_blocks_venue_id_idx on public.reservation_blocks(venue_id);
create index if not exists reservations_cancelled_by_idx on public.reservations(cancelled_by);
create index if not exists reservations_created_by_idx on public.reservations(created_by);
create index if not exists reservations_customer_profile_id_idx on public.reservations(customer_profile_id);
create index if not exists reservations_venue_id_idx on public.reservations(venue_id);
create index if not exists stations_venue_id_idx on public.stations(venue_id);
create index if not exists tournament_bracket_states_updated_by_idx on public.tournament_bracket_states(updated_by);
create index if not exists tournament_calendar_club_id_idx on public.tournament_calendar(club_id);
create index if not exists tournament_calendar_owner_id_idx on public.tournament_calendar(owner_id);
create index if not exists tournament_group_resources_created_by_idx on public.tournament_group_resources(created_by);
create index if not exists tournament_player_payments_fee_category_id_idx on public.tournament_player_payments(fee_category_id);
create index if not exists tournament_player_payments_tournament_player_id_idx on public.tournament_player_payments(tournament_player_id);
create index if not exists tournament_resource_assignments_assigned_by_idx on public.tournament_resource_assignments(assigned_by);
create index if not exists tournament_resource_assignments_winner_id_idx on public.tournament_resource_assignments(winner_id);
create index if not exists tournament_results_tournament_player_id_idx on public.tournament_results(tournament_player_id);
create index if not exists tournament_scorers_created_by_idx on public.tournament_scorers(created_by);
create index if not exists tournaments_current_phase_id_idx on public.tournaments(current_phase_id);
