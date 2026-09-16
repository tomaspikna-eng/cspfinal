create index if not exists league_match_lineups_updated_by_idx
  on public.league_match_lineups(updated_by)
  where updated_by is not null;

create index if not exists league_match_sheets_home_confirmed_by_idx
  on public.league_match_sheets(home_confirmed_by)
  where home_confirmed_by is not null;

create index if not exists league_match_sheets_away_confirmed_by_idx
  on public.league_match_sheets(away_confirmed_by)
  where away_confirmed_by is not null;
