-- P3 security hardening: keep public/token workflows working while removing
-- direct access to internal helpers and preventing capability-token leakage.

-- Internal SECURITY DEFINER helpers are callable only by their owner/service role.
revoke execute on function public.ensure_player_ihs_profile(uuid) from public, anon, authenticated;
revoke execute on function public.ensure_player_ihs_rating(uuid,text) from public, anon, authenticated;
revoke execute on function public.notify_followers_of_profile(uuid,text,text,uuid,text,text,text) from public, anon, authenticated;
revoke execute on function public.rebuild_ihs_sport(text) from public, anon, authenticated;
revoke execute on function public.resolve_or_create_player_identity(text,uuid,text) from public, anon, authenticated;
revoke execute on function public.resolve_tournament_player_profile_id(uuid,uuid) from public, anon, authenticated;
grant execute on function public.ensure_player_ihs_profile(uuid) to service_role;
grant execute on function public.ensure_player_ihs_rating(uuid,text) to service_role;
grant execute on function public.notify_followers_of_profile(uuid,text,text,uuid,text,text,text) to service_role;
grant execute on function public.rebuild_ihs_sport(text) to service_role;
grant execute on function public.resolve_or_create_player_identity(text,uuid,text) to service_role;
grant execute on function public.resolve_tournament_player_profile_id(uuid,uuid) to service_role;

-- Public IHS lookup must be read-only. Missing profile/rating rows are represented
-- by the default rating instead of being created by an anonymous read.
create or replace function public.get_public_ihs_grade(p_player_id uuid, p_sport text default null::text)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_sport text;
  v_sport_key text;
  v_rating public.player_ihs_ratings;
  v_default_rating numeric := 2.50;
  v_level text;
begin
  if p_player_id is null then
    raise exception 'Player id is required';
  end if;

  if not exists(select 1 from public.profiles p where p.id=p_player_id and p.role::text='player') then
    raise exception 'Player not found';
  end if;

  select coalesce(ip.default_rating, 2.50)
  into v_default_rating
  from public.profiles p
  left join public.player_ihs_profiles ip on ip.player_id=p.id
  where p.id=p_player_id;

  v_sport := nullif(btrim(p_sport),'');
  if v_sport is null then
    select pd.sport into v_sport
    from public.player_disciplines pd
    where pd.player_id=p_player_id
    order by pd.is_primary desc, pd.created_at asc
    limit 1;
  end if;

  if v_sport is not null then
    v_sport_key := public.normalize_ihs_sport(v_sport);
    select * into v_rating
    from public.player_ihs_ratings r
    where r.player_id=p_player_id
      and r.sport_key=v_sport_key
    limit 1;
  end if;

  v_level := coalesce(v_rating.level, public.ihs_level_for_rating(v_default_rating));

  return jsonb_build_object(
    'player_id',p_player_id,
    'sport',coalesce(v_rating.sport,v_sport),
    'grade',public.ihs_grade_for_level(v_level)
  );
end;
$function$;

-- Legacy manual station start is incompatible with the canonical lifecycle
-- (both players present -> automatic start). Keep only service-role access.
revoke execute on function public.station_start_match_clock(text) from public, anon, authenticated;
grant execute on function public.station_start_match_clock(text) to service_role;

-- Anonymous clients must never receive capability tokens. Keep public read access
-- only to the columns required by public results/realtime refreshes.
revoke all privileges on table public.matches from anon;
grant select (
  id, tournament_id, round_key, player1_id, player2_id, score1, score2, winner_id,
  status, created_at, updated_at, player1_reported_score, player1_reported_at,
  player2_reported_score, player2_reported_at, phase_id, round_number, match_number,
  bracket_side, next_match_id, loser_next_match_id, player1_source, player2_source,
  station_id, scheduled_at, called_at, arrival_deadline_at, penalty_1_at,
  penalty_2_at, penalty_3_at, forfeit_at, late_player_id, penalty_score_awarded,
  forfeit_reason, match_call_status, player1_ready_at, player2_ready_at, started_at,
  completed_at, shot_clock_enabled, shot_clock_seconds, post_break_seconds,
  extension_seconds, extensions_allowed, extensions_used_player1,
  extensions_used_player2, shot_clock_operator_id, shot_clock_started_at,
  shot_clock_paused_at, shot_clock_remaining_seconds, shot_clock_current_player_id,
  match_clock_elapsed_seconds, match_clock_started_at, match_clock_paused_at,
  match_clock_stopped_at, station_label, tournament_resource_id,
  tournament_resource_label, result_source, result_submitted_at,
  player1_timeout_active, player2_timeout_active, player1_timeout_at,
  player2_timeout_at, group_index
) on public.matches to anon;

revoke all privileges on table public.tournament_resources from anon;
grant select (
  id, tournament_id, resource_number, label, resource_type, status,
  current_match_id, is_active, sort_order, created_at, updated_at,
  tablet_paired_at, tablet_last_seen_at, tablet_name, operating_mode,
  automation_enabled
) on public.tournament_resources to anon;

-- These public-readable tables contain no capability secret, but anonymous users
-- must remain read-only.
revoke insert, update, delete, truncate, trigger, references
  on table public.tournament_resource_assignments from anon;
revoke insert, update, delete, truncate, trigger, references
  on table public.tournament_bracket_states from anon;

-- RLS remains authoritative for normal authenticated DML. Remove database-level
-- powers the browser client never needs.
revoke truncate, trigger, references on table public.matches from authenticated;
revoke truncate, trigger, references on table public.tournament_resources from authenticated;
revoke truncate, trigger, references on table public.tournament_resource_assignments from authenticated;
revoke truncate, trigger, references on table public.tournament_bracket_states from authenticated;
