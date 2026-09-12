-- CSP Database Stabilization 01
-- Safe, backward-compatible hardening and indexing.

-- 1) Pin search_path on trigger/helper functions flagged by the database advisor.
alter function public.set_updated_at() set search_path = public, pg_temp;
alter function public.set_article_published_at() set search_path = public, pg_temp;
alter function public.protect_admin_only_columns() set search_path = public, pg_temp;

-- 2) Internal trigger functions must not be callable directly through PostgREST RPC.
-- Trigger execution itself is unaffected by these revokes.
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.handle_match_self_report() from public, anon, authenticated;
revoke execute on function public.increment_tournaments_created_count() from public, anon, authenticated;
revoke execute on function public.enforce_club_manager_access() from public, anon, authenticated;
revoke execute on function public.set_updated_at() from public, anon, authenticated;
revoke execute on function public.set_article_published_at() from public, anon, authenticated;
revoke execute on function public.protect_admin_only_columns() from public, anon, authenticated;

-- 3) Cover foreign keys used by joins, profile history, and administrative queries.
create index if not exists articles_author_id_idx
  on public.articles (author_id);

create index if not exists matches_winner_id_idx
  on public.matches (winner_id);

create index if not exists tournament_groups_player_id_idx
  on public.tournament_groups (player_id);

create index if not exists tournament_players_user_id_idx
  on public.tournament_players (user_id);

create index if not exists venue_sessions_created_by_idx
  on public.venue_sessions (created_by);

-- 4) A registered CSP profile may appear only once in a tournament.
-- Guest players remain allowed because NULL user_id values are excluded.
create unique index if not exists tournament_players_tournament_user_uidx
  on public.tournament_players (tournament_id, user_id)
  where user_id is not null;

