-- Cache Auth values once per statement in RLS policies.
-- Policy predicates and role scopes remain unchanged.

alter policy "articles_admin_all" on "public"."articles" using (can_access_magazine_cms((select auth.uid()))) with check (can_access_magazine_cms((select auth.uid())));

alter policy "calendar_station_blocks_select" on "public"."calendar_station_blocks" using ((EXISTS ( SELECT 1
   FROM clubs c
  WHERE ((c.id = calendar_station_blocks.club_id) AND ((c.owner_id = (select auth.uid())) OR is_admin((select auth.uid())))))));

alter policy "calendar_station_blocks_write" on "public"."calendar_station_blocks" using ((EXISTS ( SELECT 1
   FROM clubs c
  WHERE ((c.id = calendar_station_blocks.club_id) AND ((c.owner_id = (select auth.uid())) OR is_admin((select auth.uid()))))))) with check ((EXISTS ( SELECT 1
   FROM clubs c
  WHERE ((c.id = calendar_station_blocks.club_id) AND ((c.owner_id = (select auth.uid())) OR is_admin((select auth.uid())))))));

alter policy "club_manager_live_sessions_owner_all" on "public"."club_manager_live_sessions" using ((has_club_manager_access((select auth.uid())) AND (EXISTS ( SELECT 1
   FROM clubs c
  WHERE ((c.id = club_manager_live_sessions.club_id) AND ((c.owner_id = (select auth.uid())) OR is_admin((select auth.uid())))))))) with check ((has_club_manager_access((select auth.uid())) AND (EXISTS ( SELECT 1
   FROM clubs c
  WHERE ((c.id = club_manager_live_sessions.club_id) AND ((c.owner_id = (select auth.uid())) OR is_admin((select auth.uid()))))))));

alter policy "club_manager_price_profiles_owner_all" on "public"."club_manager_price_profiles" using ((has_club_manager_access((select auth.uid())) AND (EXISTS ( SELECT 1
   FROM clubs c
  WHERE ((c.id = club_manager_price_profiles.club_id) AND ((c.owner_id = (select auth.uid())) OR is_admin((select auth.uid())))))))) with check ((has_club_manager_access((select auth.uid())) AND (EXISTS ( SELECT 1
   FROM clubs c
  WHERE ((c.id = club_manager_price_profiles.club_id) AND ((c.owner_id = (select auth.uid())) OR is_admin((select auth.uid()))))))));

alter policy "club_representatives_owner_all" on "public"."club_representatives" using (((owner_id = (select auth.uid())) OR is_admin((select auth.uid())))) with check (((owner_id = (select auth.uid())) OR is_admin((select auth.uid()))));

alter policy "clubs_owner_all" on "public"."clubs" using ((owner_id = (select auth.uid()))) with check ((owner_id = (select auth.uid())));

alter policy "event_preregistrations_owner_delete" on "public"."event_preregistrations" using ((EXISTS ( SELECT 1
   FROM events e
  WHERE ((e.id = event_preregistrations.event_id) AND (e.owner_id = (select auth.uid()))))));

alter policy "event_preregistrations_owner_select" on "public"."event_preregistrations" using ((EXISTS ( SELECT 1
   FROM events e
  WHERE ((e.id = event_preregistrations.event_id) AND (e.owner_id = (select auth.uid()))))));

alter policy "feature_gates_write_admin" on "public"."feature_gates" using (is_admin((select auth.uid()))) with check (is_admin((select auth.uid())));

alter policy "league_admins_read" on "public"."league_admins" using ((can_manage_league(league_id) OR (user_id = (select auth.uid()))));

alter policy "league_players_public_read" on "public"."league_players" using ((EXISTS ( SELECT 1
   FROM leagues l
  WHERE ((l.id = league_players.league_id) AND (((l.visibility = ANY (ARRAY['public'::text, 'unlisted'::text])) AND (l.status <> 'draft'::text)) OR can_manage_league(l.id) OR (league_players.user_id = (select auth.uid())))))));

alter policy "matches_insert_owner" on "public"."matches" with check ((EXISTS ( SELECT 1
   FROM tournaments t
  WHERE ((t.id = matches.tournament_id) AND (t.owner_id = (select auth.uid()))))));

alter policy "matches_select" on "public"."matches" using ((EXISTS ( SELECT 1
   FROM tournaments t
  WHERE ((t.id = matches.tournament_id) AND ((t.owner_id = (select auth.uid())) OR (t.status <> 'draft'::text))))));

alter policy "matches_self_report" on "public"."matches" using (((EXISTS ( SELECT 1
   FROM tournament_players tp
  WHERE ((tp.id = matches.player1_id) AND (tp.user_id = (select auth.uid()))))) OR (EXISTS ( SELECT 1
   FROM tournament_players tp
  WHERE ((tp.id = matches.player2_id) AND (tp.user_id = (select auth.uid()))))))) with check (((EXISTS ( SELECT 1
   FROM tournament_players tp
  WHERE ((tp.id = matches.player1_id) AND (tp.user_id = (select auth.uid()))))) OR (EXISTS ( SELECT 1
   FROM tournament_players tp
  WHERE ((tp.id = matches.player2_id) AND (tp.user_id = (select auth.uid())))))));

alter policy "matches_update_owner" on "public"."matches" using ((EXISTS ( SELECT 1
   FROM tournaments t
  WHERE ((t.id = matches.tournament_id) AND (t.owner_id = (select auth.uid())))))) with check ((EXISTS ( SELECT 1
   FROM tournaments t
  WHERE ((t.id = matches.tournament_id) AND (t.owner_id = (select auth.uid()))))));

alter policy "organizations_select_own" on "public"."organizations" using (((owner_id = (select auth.uid())) OR is_admin((select auth.uid()))));

alter policy "organizations_update_own" on "public"."organizations" using (((owner_id = (select auth.uid())) OR is_admin((select auth.uid())))) with check (((owner_id = (select auth.uid())) OR is_admin((select auth.uid()))));

alter policy "player_ihs_ratings_read_own" on "public"."player_ihs_ratings" using (((player_id = (select auth.uid())) OR is_admin((select auth.uid()))));

alter policy "profiles_update_admin" on "public"."profiles" using (is_admin((select auth.uid()))) with check (is_admin((select auth.uid())));

alter policy "profiles_update_own" on "public"."profiles" using ((id = (select auth.uid()))) with check ((id = (select auth.uid())));

alter policy "reservations_customer_read" on "public"."reservations" using ((customer_profile_id = (select auth.uid())));

alter policy "stations_owner_all" on "public"."stations" using ((EXISTS ( SELECT 1
   FROM clubs c
  WHERE ((c.id = stations.club_id) AND (c.owner_id = (select auth.uid())))))) with check ((EXISTS ( SELECT 1
   FROM clubs c
  WHERE ((c.id = stations.club_id) AND (c.owner_id = (select auth.uid()))))));

alter policy "tournament_bracket_states_owner_select" on "public"."tournament_bracket_states" using ((EXISTS ( SELECT 1
   FROM tournaments t
  WHERE ((t.id = tournament_bracket_states.tournament_id) AND ((t.owner_id = (select auth.uid())) OR is_admin((select auth.uid())))))));

alter policy "tournament_bracket_states_owner_write" on "public"."tournament_bracket_states" using ((EXISTS ( SELECT 1
   FROM tournaments t
  WHERE ((t.id = tournament_bracket_states.tournament_id) AND ((t.owner_id = (select auth.uid())) OR is_admin((select auth.uid()))))))) with check ((EXISTS ( SELECT 1
   FROM tournaments t
  WHERE ((t.id = tournament_bracket_states.tournament_id) AND ((t.owner_id = (select auth.uid())) OR is_admin((select auth.uid())))))));

alter policy "tournament_calendar_owner_all" on "public"."tournament_calendar" using ((owner_id = (select auth.uid()))) with check ((owner_id = (select auth.uid())));

alter policy "tournament_display_settings_owner_delete" on "public"."tournament_display_settings" using ((EXISTS ( SELECT 1
   FROM tournaments t
  WHERE ((t.id = tournament_display_settings.tournament_id) AND ((t.owner_id = (select auth.uid())) OR is_admin((select auth.uid())))))));

alter policy "tournament_display_settings_owner_insert" on "public"."tournament_display_settings" with check ((EXISTS ( SELECT 1
   FROM tournaments t
  WHERE ((t.id = tournament_display_settings.tournament_id) AND ((t.owner_id = (select auth.uid())) OR is_admin((select auth.uid())))))));

alter policy "tournament_display_settings_owner_select" on "public"."tournament_display_settings" using ((EXISTS ( SELECT 1
   FROM tournaments t
  WHERE ((t.id = tournament_display_settings.tournament_id) AND ((t.owner_id = (select auth.uid())) OR is_admin((select auth.uid())))))));

alter policy "tournament_display_settings_owner_update" on "public"."tournament_display_settings" using ((EXISTS ( SELECT 1
   FROM tournaments t
  WHERE ((t.id = tournament_display_settings.tournament_id) AND ((t.owner_id = (select auth.uid())) OR is_admin((select auth.uid()))))))) with check ((EXISTS ( SELECT 1
   FROM tournaments t
  WHERE ((t.id = tournament_display_settings.tournament_id) AND ((t.owner_id = (select auth.uid())) OR is_admin((select auth.uid())))))));

alter policy "tournament_group_resources_owner_all" on "public"."tournament_group_resources" using ((EXISTS ( SELECT 1
   FROM tournaments t
  WHERE ((t.id = tournament_group_resources.tournament_id) AND ((t.owner_id = (select auth.uid())) OR is_admin((select auth.uid()))))))) with check ((EXISTS ( SELECT 1
   FROM tournaments t
  WHERE ((t.id = tournament_group_resources.tournament_id) AND ((t.owner_id = (select auth.uid())) OR is_admin((select auth.uid())))))));

alter policy "tournament_groups_owner_write" on "public"."tournament_groups" using ((EXISTS ( SELECT 1
   FROM tournaments t
  WHERE ((t.id = tournament_groups.tournament_id) AND (t.owner_id = (select auth.uid())))))) with check ((EXISTS ( SELECT 1
   FROM tournaments t
  WHERE ((t.id = tournament_groups.tournament_id) AND (t.owner_id = (select auth.uid()))))));

alter policy "tournament_groups_select" on "public"."tournament_groups" using ((EXISTS ( SELECT 1
   FROM tournaments t
  WHERE ((t.id = tournament_groups.tournament_id) AND ((t.owner_id = (select auth.uid())) OR (t.status <> 'draft'::text))))));

alter policy "tournament_players_owner_write" on "public"."tournament_players" using ((EXISTS ( SELECT 1
   FROM tournaments t
  WHERE ((t.id = tournament_players.tournament_id) AND (t.owner_id = (select auth.uid())))))) with check ((EXISTS ( SELECT 1
   FROM tournaments t
  WHERE ((t.id = tournament_players.tournament_id) AND (t.owner_id = (select auth.uid()))))));

alter policy "tournament_players_select" on "public"."tournament_players" using ((EXISTS ( SELECT 1
   FROM tournaments t
  WHERE ((t.id = tournament_players.tournament_id) AND ((t.owner_id = (select auth.uid())) OR (t.status <> 'draft'::text))))));

alter policy "tournament_resource_assignments_owner_all" on "public"."tournament_resource_assignments" using ((EXISTS ( SELECT 1
   FROM tournaments t
  WHERE ((t.id = tournament_resource_assignments.tournament_id) AND ((t.owner_id = (select auth.uid())) OR is_admin((select auth.uid()))))))) with check ((EXISTS ( SELECT 1
   FROM tournaments t
  WHERE ((t.id = tournament_resource_assignments.tournament_id) AND ((t.owner_id = (select auth.uid())) OR is_admin((select auth.uid())))))));

alter policy "tournament_resources_owner_all" on "public"."tournament_resources" using ((EXISTS ( SELECT 1
   FROM tournaments t
  WHERE ((t.id = tournament_resources.tournament_id) AND ((t.owner_id = (select auth.uid())) OR is_admin((select auth.uid()))))))) with check ((EXISTS ( SELECT 1
   FROM tournaments t
  WHERE ((t.id = tournament_resources.tournament_id) AND ((t.owner_id = (select auth.uid())) OR is_admin((select auth.uid())))))));

alter policy "tournament_scorers_owner_all" on "public"."tournament_scorers" using ((EXISTS ( SELECT 1
   FROM tournaments t
  WHERE ((t.id = tournament_scorers.tournament_id) AND ((t.owner_id = (select auth.uid())) OR is_admin((select auth.uid()))))))) with check ((EXISTS ( SELECT 1
   FROM tournaments t
  WHERE ((t.id = tournament_scorers.tournament_id) AND ((t.owner_id = (select auth.uid())) OR is_admin((select auth.uid())))))));

alter policy "training_sessions_delete_owner" on "public"."training_sessions" using ((owner_id = (select auth.uid())));

alter policy "training_sessions_insert_owner" on "public"."training_sessions" with check ((owner_id = (select auth.uid())));

alter policy "training_sessions_select_owner" on "public"."training_sessions" using ((owner_id = (select auth.uid())));

alter policy "venue_pricing_rules_owner_all" on "public"."venue_pricing_rules" using ((EXISTS ( SELECT 1
   FROM (venues v
     JOIN clubs c ON ((c.id = v.club_id)))
  WHERE ((v.id = venue_pricing_rules.venue_id) AND (c.owner_id = (select auth.uid())))))) with check ((EXISTS ( SELECT 1
   FROM (venues v
     JOIN clubs c ON ((c.id = v.club_id)))
  WHERE ((v.id = venue_pricing_rules.venue_id) AND (c.owner_id = (select auth.uid()))))));

alter policy "venue_sessions_owner_all" on "public"."venue_sessions" using ((EXISTS ( SELECT 1
   FROM (venues v
     JOIN clubs c ON ((c.id = v.club_id)))
  WHERE ((v.id = venue_sessions.venue_id) AND (c.owner_id = (select auth.uid())))))) with check ((EXISTS ( SELECT 1
   FROM (venues v
     JOIN clubs c ON ((c.id = v.club_id)))
  WHERE ((v.id = venue_sessions.venue_id) AND (c.owner_id = (select auth.uid()))))));

alter policy "venues_owner_all" on "public"."venues" using ((EXISTS ( SELECT 1
   FROM clubs c
  WHERE ((c.id = venues.club_id) AND (c.owner_id = (select auth.uid())))))) with check ((EXISTS ( SELECT 1
   FROM clubs c
  WHERE ((c.id = venues.club_id) AND (c.owner_id = (select auth.uid()))))));

