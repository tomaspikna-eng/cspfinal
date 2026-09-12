begin;

-- Kaniansky pohár 2026 · historický import po 6. kole.
-- Zdroj: poradie organizátora zo 6. 9. 2026.
-- Hlavička zdroja uvádza pri 3. kole 7 hráčov, ale obsahuje 8 bodovaných výsledkov.
-- Import preto buniek (8 výsledkov) reprodukuje všetky celkové súčty a poradie.

-- Historické bodovanie Kanianskeho pohára:
-- 1. = 200, 2. = 150, 3. = 120, 4. = 100,
-- 5.–6. = 70, 7.–8. = 50, 9. a ďalší = 30.
-- Bez bonusu za účasť a bez dodatočných tie-breakov.

alter table public.event_series
  alter column ranking_config set default
  '{"version":2,"preset":"kanianka_200","method":"placement_points","best_results_count":null,"attendance_bonus":0,"points":[{"min_position":1,"max_position":1,"points":200},{"min_position":2,"max_position":2,"points":150},{"min_position":3,"max_position":3,"points":120},{"min_position":4,"max_position":4,"points":100},{"min_position":5,"max_position":6,"points":70},{"min_position":7,"max_position":8,"points":50},{"min_position":9,"max_position":null,"points":30}],"tie_breakers":[]}'::jsonb;

update public.event_series s
set ranking_config =
  '{"version":2,"preset":"kanianka_200","method":"placement_points","best_results_count":null,"attendance_bonus":0,"points":[{"min_position":1,"max_position":1,"points":200},{"min_position":2,"max_position":2,"points":150},{"min_position":3,"max_position":3,"points":120},{"min_position":4,"max_position":4,"points":100},{"min_position":5,"max_position":6,"points":70},{"min_position":7,"max_position":8,"points":50},{"min_position":9,"max_position":null,"points":30}],"tie_breakers":[]}'::jsonb
where s.ranking_config ->> 'preset' = 'kanianka_200'
  and not exists (
    select 1
    from public.events e
    join public.tournaments t on t.source_event_id = e.id
    where e.series_id = s.id
      and t.status in ('completed', 'archived')
  );

-- Rebríček rešpektuje nastavené tie-breaky série. Prázdny zoznam znamená
-- zhodné miesto pri rovnakom počte bodov (napr. 4., 4., 6.).
create or replace view public.event_series_standings
with (security_invoker = true)
as
with aggregated as (
  select
    r.series_id,
    r.series_title,
    r.total_rounds,
    r.best_results_count,
    coalesce(s.ranking_config -> 'tie_breakers', '[]'::jsonb) as tie_breakers,
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
  join public.event_series s on s.id = r.series_id
  group by
    r.series_id,
    r.series_title,
    r.total_rounds,
    r.best_results_count,
    s.ranking_config,
    r.player_identity_id
), ranked as (
  select
    a.*,
    rank() over (
      partition by a.series_id
      order by
        a.total_points desc,
        case when a.tie_breakers ? 'victories' then a.victories end desc nulls last,
        case when a.tie_breakers ? 'runner_up_finishes' then a.runner_up_finishes end desc nulls last,
        case when a.tie_breakers ? 'third_places' then a.third_places end desc nulls last,
        case when a.tie_breakers ? 'best_position' then a.best_position end asc nulls last,
        case when a.tie_breakers ? 'match_wins' then a.match_wins end desc nulls last
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
  'Public read-only overall series standings. Tie-breakers are applied only when listed in event_series.ranking_config; rank preserves shared places.';

insert into public.event_series (
  id, owner_id, club_id, title, event_type, sport, discipline,
  total_rounds, status, visibility, ranking_config
)
values (
  '7c52107d-a4b0-4b81-9f6f-202609060001',
  'cd151097-1abd-41ee-a4f3-aff9eff8bace',
  'c42c0115-b603-4811-8807-ab51526b210d',
  'Kaniansky pohár 2026 · XXIII. ročník',
  'Turnaj',
  'Biliard',
  '8-ball / 9-ball',
  10,
  'published',
  'public',
  '{"version":2,"preset":"kanianka_200","method":"placement_points","best_results_count":null,"attendance_bonus":0,"points":[{"min_position":1,"max_position":1,"points":200},{"min_position":2,"max_position":2,"points":150},{"min_position":3,"max_position":3,"points":120},{"min_position":4,"max_position":4,"points":100},{"min_position":5,"max_position":6,"points":70},{"min_position":7,"max_position":8,"points":50},{"min_position":9,"max_position":null,"points":30}],"tie_breakers":[]}'::jsonb
)
on conflict (id) do update set
  owner_id = excluded.owner_id,
  club_id = excluded.club_id,
  title = excluded.title,
  event_type = excluded.event_type,
  sport = excluded.sport,
  discipline = excluded.discipline,
  total_rounds = excluded.total_rounds,
  status = excluded.status,
  visibility = excluded.visibility,
  ranking_config = excluded.ranking_config,
  updated_at = now();

create temp table kanianka_round_import (
  round_number smallint primary key,
  event_id uuid not null unique,
  tournament_id uuid not null unique,
  event_date date not null,
  starts_at timestamptz not null,
  discipline text not null,
  declared_player_count integer not null
) on commit drop;

insert into kanianka_round_import values
  (1, '7c52107d-a4b0-4b81-9f6f-202609060101', '7c52107d-a4b0-4b81-9f6f-202609060201', date '2026-01-18', timestamptz '2026-01-18 10:00:00+01', '8-ball', 10),
  (2, '7c52107d-a4b0-4b81-9f6f-202609060102', '7c52107d-a4b0-4b81-9f6f-202609060202', date '2026-02-15', timestamptz '2026-02-15 10:00:00+01', '8-ball', 9),
  (3, '7c52107d-a4b0-4b81-9f6f-202609060103', '7c52107d-a4b0-4b81-9f6f-202609060203', date '2026-03-15', timestamptz '2026-03-15 10:00:00+01', '8-ball', 7),
  (4, '7c52107d-a4b0-4b81-9f6f-202609060104', '7c52107d-a4b0-4b81-9f6f-202609060204', date '2026-04-12', timestamptz '2026-04-12 10:00:00+02', '8-ball', 11),
  (5, '7c52107d-a4b0-4b81-9f6f-202609060105', '7c52107d-a4b0-4b81-9f6f-202609060205', date '2026-05-10', timestamptz '2026-05-10 10:00:00+02', '9-ball', 10),
  (6, '7c52107d-a4b0-4b81-9f6f-202609060106', '7c52107d-a4b0-4b81-9f6f-202609060206', date '2026-06-07', timestamptz '2026-06-07 10:00:00+02', '8-ball', 8);

create temp table kanianka_player_import (
  display_name text primary key,
  source_registration_flag text not null
) on commit drop;

insert into kanianka_player_import values
  ('Veis', 'N'),
  ('Komáromi', 'N'),
  ('Píkna', 'N'),
  ('Kvostka', 'N'),
  ('Pastucha', 'N'),
  ('Čertík', 'A'),
  ('Foltán F.', 'A'),
  ('Foltán I.', 'N'),
  ('Gonda', 'N'),
  ('Gašpar', 'N'),
  ('Matlovič', 'N'),
  ('Trgiňa', 'N'),
  ('Mihály', 'N'),
  ('Sľuka J.', 'N'),
  ('Gurtler Š.', 'N'),
  ('Mihályová', 'N'),
  ('Gaman', 'N'),
  ('Varholák', 'N');

create temp table kanianka_result_import (
  round_number smallint not null,
  display_name text not null,
  final_position integer not null,
  source_points integer not null,
  primary key (round_number, display_name)
) on commit drop;

insert into kanianka_result_import values
  (1, 'Foltán F.', 1, 200),
  (1, 'Matlovič', 2, 150),
  (1, 'Kvostka', 3, 120),
  (1, 'Foltán I.', 4, 100),
  (1, 'Komáromi', 5, 70),
  (1, 'Pastucha', 6, 70),
  (1, 'Píkna', 7, 50),
  (1, 'Trgiňa', 8, 50),
  (1, 'Mihályová', 9, 30),
  (1, 'Varholák', 10, 30),

  (2, 'Čertík', 1, 200),
  (2, 'Veis', 2, 150),
  (2, 'Kvostka', 3, 120),
  (2, 'Komáromi', 4, 100),
  (2, 'Foltán I.', 5, 70),
  (2, 'Mihály', 6, 70),
  (2, 'Pastucha', 7, 50),
  (2, 'Gurtler Š.', 8, 50),
  (2, 'Píkna', 9, 30),

  (3, 'Veis', 1, 200),
  (3, 'Komáromi', 2, 150),
  (3, 'Píkna', 3, 120),
  (3, 'Pastucha', 4, 100),
  (3, 'Foltán I.', 5, 70),
  (3, 'Trgiňa', 6, 70),
  (3, 'Gašpar', 7, 50),
  (3, 'Gaman', 8, 50),

  (4, 'Foltán F.', 1, 200),
  (4, 'Veis', 2, 150),
  (4, 'Sľuka J.', 3, 120),
  (4, 'Kvostka', 4, 100),
  (4, 'Komáromi', 5, 70),
  (4, 'Pastucha', 6, 70),
  (4, 'Foltán I.', 7, 50),
  (4, 'Mihály', 8, 50),
  (4, 'Píkna', 9, 30),
  (4, 'Gašpar', 10, 30),
  (4, 'Mihályová', 11, 30),

  (5, 'Gonda', 1, 200),
  (5, 'Veis', 2, 150),
  (5, 'Píkna', 3, 120),
  (5, 'Komáromi', 4, 100),
  (5, 'Pastucha', 5, 70),
  (5, 'Čertík', 6, 70),
  (5, 'Kvostka', 7, 50),
  (5, 'Foltán I.', 8, 50),
  (5, 'Gašpar', 9, 30),
  (5, 'Mihályová', 10, 30),

  (6, 'Veis', 1, 200),
  (6, 'Čertík', 2, 150),
  (6, 'Píkna', 3, 120),
  (6, 'Pastucha', 4, 100),
  (6, 'Komáromi', 5, 70),
  (6, 'Kvostka', 6, 70),
  (6, 'Gašpar', 7, 50),
  (6, 'Gurtler Š.', 8, 50);

-- Vytvor neprevzaté identity iba tam, kde ešte neexistujú.
-- Gurtler Š. sa nižšie mapuje na existujúcu prevzatú identitu Stefan Gurtler.
insert into public.player_identities (
  csp_number, display_name, normalized_name, status, created_source, created_by
)
select
  nextval('public.player_identities_csp_number_seq'),
  p.display_name,
  public.normalize_player_identity_name(p.display_name),
  'unclaimed',
  'historical_import',
  'cd151097-1abd-41ee-a4f3-aff9eff8bace'
from kanianka_player_import p
where p.display_name <> 'Gurtler Š.'
  and not exists (
    select 1
    from public.player_identities pi
    where pi.normalized_name = public.normalize_player_identity_name(p.display_name)
      and pi.status <> 'merged'
  );

-- Pri importe starých verejných udalostí nechceme rozoslať šesť nových notifikácií.
alter table public.events disable trigger events_notify_followers_published;

insert into public.events (
  id, owner_id, club_id, title, description, sport, discipline,
  location_text, starts_at, ends_at, status, event_type, cover_image_url,
  city, visibility, registration_enabled, published_at,
  series_id, series_round_number
)
select
  r.event_id,
  'cd151097-1abd-41ee-a4f3-aff9eff8bace',
  'c42c0115-b603-4811-8807-ab51526b210d',
  'Kaniansky pohár 2026 · ' || r.round_number || '. kolo',
  'Historický výsledok importovaný z oficiálneho poradia Kanianskeho pohára 2026.',
  'Biliard',
  r.discipline,
  'Moment Club',
  r.starts_at,
  r.starts_at + interval '8 hours',
  'published',
  'Turnaj',
  'https://lcmoykaqvvfybtobhtqg.supabase.co/storage/v1/object/public/event-covers/cd151097-1abd-41ee-a4f3-aff9eff8bace/627ca184-6feb-408f-9e0e-f65be63f71db.png',
  'Kanianka',
  'public',
  false,
  r.starts_at,
  '7c52107d-a4b0-4b81-9f6f-202609060001',
  r.round_number
from kanianka_round_import r
on conflict (id) do update set
  title = excluded.title,
  discipline = excluded.discipline,
  starts_at = excluded.starts_at,
  ends_at = excluded.ends_at,
  status = excluded.status,
  visibility = excluded.visibility,
  registration_enabled = excluded.registration_enabled,
  series_id = excluded.series_id,
  series_round_number = excluded.series_round_number,
  updated_at = now();

update public.events
set
  series_id = '7c52107d-a4b0-4b81-9f6f-202609060001',
  series_round_number = 7,
  updated_at = now()
where id = '993347f7-00de-4904-8880-3de63a7f325e';

alter table public.events enable trigger events_notify_followers_published;

-- Import sa nemá započítať do kvóty novovytvorených turnajov organizátora.
alter table public.tournaments disable trigger tournaments_increment_owner_count;

insert into public.tournaments (
  id, owner_id, name, sport, discipline, format, date, venue,
  status, started_at, completed_at, archived_at, config,
  country, city, organizer_name, visibility, registration_enabled,
  source_event_id
)
select
  r.tournament_id,
  'cd151097-1abd-41ee-a4f3-aff9eff8bace',
  'Kaniansky pohár 2026 · ' || r.round_number || '. kolo',
  'Biliard',
  r.discipline,
  'dko',
  r.event_date,
  'Moment Club',
  'archived',
  r.starts_at,
  r.starts_at + interval '8 hours',
  r.starts_at + interval '8 hours',
  jsonb_build_object(
    'historical_import', true,
    'source', 'Kaniansky pohár 2026 · poradie po 6. kole',
    'declared_player_count', r.declared_player_count,
    'imported_result_count', (
      select count(*) from kanianka_result_import x where x.round_number = r.round_number
    ),
    'source_count_discrepancy', r.declared_player_count <> (
      select count(*) from kanianka_result_import x where x.round_number = r.round_number
    )
  ),
  'Slovenská republika',
  'Kanianka',
  'CSP',
  'public',
  false,
  r.event_id
from kanianka_round_import r
on conflict (id) do nothing;

alter table public.tournaments enable trigger tournaments_increment_owner_count;

with resolved as (
  select
    x.round_number,
    x.display_name,
    x.final_position,
    x.source_points,
    r.tournament_id,
    p.source_registration_flag,
    case
      when x.display_name = 'Gurtler Š.' then '84320c56-dcdf-48e0-86d0-18d77daf55b8'::uuid
      else (
        select pi.id
        from public.player_identities pi
        where pi.normalized_name = public.normalize_player_identity_name(x.display_name)
          and pi.status <> 'merged'
        order by (pi.status = 'claimed') desc, pi.created_at
        limit 1
      )
    end as player_identity_id
  from kanianka_result_import x
  join kanianka_round_import r using (round_number)
  join kanianka_player_import p using (display_name)
)
insert into public.tournament_players (
  tournament_id, name, user_id, seed, player_identity_id
)
select
  x.tournament_id,
  x.display_name,
  pi.claimed_profile_id,
  x.final_position,
  x.player_identity_id
from resolved x
join public.player_identities pi on pi.id = x.player_identity_id
where not exists (
  select 1
  from public.tournament_players tp
  where tp.tournament_id = x.tournament_id
    and tp.player_identity_id = x.player_identity_id
);

insert into public.tournament_results (
  tournament_id, tournament_player_id, user_id, final_position,
  matches_played, wins, losses, score_for, score_against, metadata
)
select
  r.tournament_id,
  tp.id,
  tp.user_id,
  x.final_position,
  0, 0, 0, 0, 0,
  jsonb_build_object(
    'historical_import', true,
    'source_points', x.source_points,
    'source_registration_flag', p.source_registration_flag,
    'match_statistics_available', false
  )
from kanianka_result_import x
join kanianka_round_import r using (round_number)
join kanianka_player_import p using (display_name)
join public.tournament_players tp
  on tp.tournament_id = r.tournament_id
 and tp.name = x.display_name
on conflict (tournament_id, tournament_player_id) do update set
  user_id = excluded.user_id,
  final_position = excluded.final_position,
  metadata = excluded.metadata,
  updated_at = now();

-- Importované body musia byť identické so zdrojom. Ak nie, celá transakcia sa zruší.
do $$
declare
  v_mismatch_count integer;
begin
  select count(*)
  into v_mismatch_count
  from kanianka_result_import src
  join kanianka_round_import ri using (round_number)
  join public.tournament_players tp
    on tp.tournament_id = ri.tournament_id
   and tp.name = src.display_name
  join public.event_series_round_scores score
    on score.tournament_id = ri.tournament_id
   and score.tournament_player_id = tp.id
  where score.points <> src.source_points;

  if v_mismatch_count <> 0 then
    raise exception 'KANIANKA_IMPORT_POINT_MISMATCH: %', v_mismatch_count;
  end if;

  if (select count(*) from public.event_series_round_scores
      where series_id = '7c52107d-a4b0-4b81-9f6f-202609060001') <> 56 then
    raise exception 'KANIANKA_IMPORT_EXPECTED_56_ROUND_RESULTS';
  end if;
end;
$$;

commit;

