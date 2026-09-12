create or replace function public.get_tournament_display_view(p_tournament_id uuid)
returns table(
  tournament_id uuid,
  tournament_name text,
  sport text,
  discipline text,
  tournament_date date,
  venue text,
  tournament_status text,
  visibility text,
  resource_id uuid,
  resource_label text,
  resource_number integer,
  resource_type text,
  resource_status text,
  sort_order integer,
  match_id uuid,
  round_key text,
  match_number integer,
  group_index integer,
  match_status text,
  player1_id uuid,
  player1_name text,
  player2_id uuid,
  player2_name text,
  score1 integer,
  score2 integer,
  started_at timestamptz,
  match_clock_elapsed_seconds integer,
  match_clock_started_at timestamptz,
  match_clock_paused_at timestamptz,
  server_now timestamptz
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    t.id as tournament_id,
    t.name as tournament_name,
    t.sport,
    t.discipline,
    t.date as tournament_date,
    t.venue,
    t.status as tournament_status,
    t.visibility,
    r.id as resource_id,
    r.label as resource_label,
    r.resource_number,
    r.resource_type,
    r.status as resource_status,
    r.sort_order,
    m.id as match_id,
    m.round_key,
    m.match_number,
    m.group_index,
    m.status as match_status,
    m.player1_id,
    p1.name as player1_name,
    m.player2_id,
    p2.name as player2_name,
    coalesce(m.score1, 0) as score1,
    coalesce(m.score2, 0) as score2,
    m.started_at,
    coalesce(m.match_clock_elapsed_seconds, 0) as match_clock_elapsed_seconds,
    m.match_clock_started_at,
    m.match_clock_paused_at,
    now() as server_now
  from public.tournaments t
  left join public.tournament_resources r
    on r.tournament_id = t.id
   and r.is_active = true
  left join public.matches m
    on m.id = r.current_match_id
   and m.tournament_id = t.id
  left join public.tournament_players p1 on p1.id = m.player1_id
  left join public.tournament_players p2 on p2.id = m.player2_id
  where t.id = p_tournament_id
    and (
      (t.status <> 'draft' and t.visibility in ('public','unlisted'))
      or t.owner_id = auth.uid()
      or public.is_admin(auth.uid())
    )
  order by r.sort_order nulls last, r.resource_number nulls last;
$$;

revoke all on function public.get_tournament_display_view(uuid) from public;
grant execute on function public.get_tournament_display_view(uuid) to anon, authenticated;

comment on function public.get_tournament_display_view(uuid) is
'Public/owner-safe data feed for CSP Display View. Returns tournament metadata plus active tournament resources and their current matches.';

