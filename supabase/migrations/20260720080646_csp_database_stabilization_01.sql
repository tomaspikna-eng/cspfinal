-- CSP database stabilization 01
alter function public.set_updated_at() set search_path = public, pg_temp;
alter function public.set_article_published_at() set search_path = public, pg_temp;
alter function public.protect_admin_only_columns() set search_path = public, pg_temp;

revoke execute on function public.handle_new_user() from anon, authenticated;
revoke execute on function public.handle_match_self_report() from anon, authenticated;
revoke execute on function public.increment_tournaments_created_count() from anon, authenticated;
revoke execute on function public.enforce_club_manager_access() from anon, authenticated;
revoke execute on function public.set_updated_at() from anon, authenticated;
revoke execute on function public.set_article_published_at() from anon, authenticated;
revoke execute on function public.protect_admin_only_columns() from anon, authenticated;

create index if not exists articles_author_id_idx on public.articles(author_id);
create index if not exists matches_winner_id_idx on public.matches(winner_id);
create index if not exists tournament_groups_player_id_idx on public.tournament_groups(player_id);
create index if not exists tournament_players_user_id_idx on public.tournament_players(user_id);
create index if not exists venue_sessions_created_by_idx on public.venue_sessions(created_by);
create unique index if not exists tournament_players_tournament_user_uidx
  on public.tournament_players(tournament_id,user_id) where user_id is not null;
