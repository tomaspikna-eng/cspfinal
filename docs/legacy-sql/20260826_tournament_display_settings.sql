create table if not exists public.tournament_display_settings (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null unique references public.tournaments(id) on delete cascade,
  public_token uuid not null unique default gen_random_uuid(),
  content_mode text not null default 'display' check (content_mode in ('list','display','dynamic')),
  selected_resource_ids uuid[] null,
  layout text not null default 'auto' check (layout in ('auto','portrait_auto','portrait_6','landscape_5x2','landscape_4x2','landscape_3x2','landscape_2x2')),
  show_live boolean not null default true,
  show_next boolean not null default true,
  show_finished boolean not null default false,
  show_match_time boolean not null default true,
  show_race_to boolean not null default true,
  show_discipline boolean not null default true,
  dynamic_interval_seconds integer not null default 30 check (dynamic_interval_seconds between 10 and 300),
  dynamic_auto boolean not null default false,
  is_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists tournament_display_settings_public_token_idx
  on public.tournament_display_settings(public_token);

alter table public.tournament_display_settings enable row level security;

drop policy if exists tournament_display_settings_owner_select on public.tournament_display_settings;
create policy tournament_display_settings_owner_select
on public.tournament_display_settings
for select
to authenticated
using (
  exists (
    select 1 from public.tournaments t
    where t.id = tournament_display_settings.tournament_id
      and (t.owner_id = auth.uid() or public.is_admin(auth.uid()))
  )
);

drop policy if exists tournament_display_settings_owner_insert on public.tournament_display_settings;
create policy tournament_display_settings_owner_insert
on public.tournament_display_settings
for insert
to authenticated
with check (
  exists (
    select 1 from public.tournaments t
    where t.id = tournament_display_settings.tournament_id
      and (t.owner_id = auth.uid() or public.is_admin(auth.uid()))
  )
);

drop policy if exists tournament_display_settings_owner_update on public.tournament_display_settings;
create policy tournament_display_settings_owner_update
on public.tournament_display_settings
for update
to authenticated
using (
  exists (
    select 1 from public.tournaments t
    where t.id = tournament_display_settings.tournament_id
      and (t.owner_id = auth.uid() or public.is_admin(auth.uid()))
  )
)
with check (
  exists (
    select 1 from public.tournaments t
    where t.id = tournament_display_settings.tournament_id
      and (t.owner_id = auth.uid() or public.is_admin(auth.uid()))
  )
);

drop policy if exists tournament_display_settings_owner_delete on public.tournament_display_settings;
create policy tournament_display_settings_owner_delete
on public.tournament_display_settings
for delete
to authenticated
using (
  exists (
    select 1 from public.tournaments t
    where t.id = tournament_display_settings.tournament_id
      and (t.owner_id = auth.uid() or public.is_admin(auth.uid()))
  )
);

drop trigger if exists tournament_display_settings_set_updated_at on public.tournament_display_settings;
create trigger tournament_display_settings_set_updated_at
before update on public.tournament_display_settings
for each row execute function public.set_updated_at();

create or replace function public.ensure_tournament_display_settings(p_tournament_id uuid)
returns public.tournament_display_settings
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.tournament_display_settings%rowtype;
begin
  if auth.uid() is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if not exists (
    select 1 from public.tournaments t
    where t.id = p_tournament_id
      and (t.owner_id = auth.uid() or public.is_admin(auth.uid()))
  ) then
    raise exception 'TOURNAMENT_NOT_FOUND_OR_FORBIDDEN';
  end if;

  insert into public.tournament_display_settings(tournament_id)
  values (p_tournament_id)
  on conflict (tournament_id) do nothing;

  select * into v_row
  from public.tournament_display_settings
  where tournament_id = p_tournament_id;

  return v_row;
end;
$$;

revoke all on function public.ensure_tournament_display_settings(uuid) from public;
grant execute on function public.ensure_tournament_display_settings(uuid) to authenticated;

create or replace function public.get_tournament_display_payload(p_public_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_settings public.tournament_display_settings%rowtype;
  v_tournament public.tournaments%rowtype;
  v_resources jsonb := '[]'::jsonb;
  v_matches jsonb := '[]'::jsonb;
begin
  select * into v_settings
  from public.tournament_display_settings
  where public_token = p_public_token
    and is_enabled = true;

  if v_settings.id is null then
    return null;
  end if;

  select * into v_tournament
  from public.tournaments
  where id = v_settings.tournament_id;

  if v_tournament.id is null then
    return null;
  end if;

  select coalesce(jsonb_agg(x.obj order by x.resource_number), '[]'::jsonb)
  into v_resources
  from (
    select
      r.resource_number,
      jsonb_build_object(
        'resource_id', r.id,
        'resource_number', r.resource_number,
        'resource_label', r.label,
        'resource_type', r.resource_type,
        'resource_status', r.status,
        'match_id', m.id,
        'match_number', m.match_number,
        'round_key', m.round_key,
        'match_status', m.status,
        'player1_name', p1.name,
        'player2_name', p2.name,
        'score1', coalesce(m.score1, 0),
        'score2', coalesce(m.score2, 0),
        'started_at', m.started_at,
        'completed_at', m.completed_at,
        'match_clock_elapsed_seconds', coalesce(m.match_clock_elapsed_seconds, 0),
        'match_clock_started_at', m.match_clock_started_at,
        'match_clock_paused_at', m.match_clock_paused_at,
        'match_clock_stopped_at', m.match_clock_stopped_at
      ) as obj
    from public.tournament_resources r
    left join public.matches m on m.id = r.current_match_id
    left join public.tournament_players p1 on p1.id = m.player1_id
    left join public.tournament_players p2 on p2.id = m.player2_id
    where r.tournament_id = v_tournament.id
      and r.is_active = true
      and (
        v_settings.selected_resource_ids is null
        or r.id = any(v_settings.selected_resource_ids)
      )
  ) x;

  select coalesce(jsonb_agg(x.obj order by x.sort_match_number, x.sort_created_at), '[]'::jsonb)
  into v_matches
  from (
    select
      coalesce(m.match_number, 2147483647) as sort_match_number,
      m.created_at as sort_created_at,
      jsonb_build_object(
        'match_id', m.id,
        'match_number', m.match_number,
        'round_key', m.round_key,
        'round_number', m.round_number,
        'status', m.status,
        'player1_name', p1.name,
        'player2_name', p2.name,
        'score1', coalesce(m.score1, 0),
        'score2', coalesce(m.score2, 0),
        'resource_id', m.tournament_resource_id,
        'resource_label', coalesce(m.tournament_resource_label, m.station_label),
        'started_at', m.started_at,
        'completed_at', m.completed_at,
        'match_clock_elapsed_seconds', coalesce(m.match_clock_elapsed_seconds, 0),
        'match_clock_started_at', m.match_clock_started_at,
        'match_clock_paused_at', m.match_clock_paused_at,
        'match_clock_stopped_at', m.match_clock_stopped_at
      ) as obj
    from public.matches m
    left join public.tournament_players p1 on p1.id = m.player1_id
    left join public.tournament_players p2 on p2.id = m.player2_id
    where m.tournament_id = v_tournament.id
      and (
        v_settings.selected_resource_ids is null
        or m.tournament_resource_id is null
        or m.tournament_resource_id = any(v_settings.selected_resource_ids)
      )
  ) x;

  return jsonb_build_object(
    'server_now', now(),
    'settings', jsonb_build_object(
      'content_mode', v_settings.content_mode,
      'selected_resource_ids', v_settings.selected_resource_ids,
      'layout', v_settings.layout,
      'show_live', v_settings.show_live,
      'show_next', v_settings.show_next,
      'show_finished', v_settings.show_finished,
      'show_match_time', v_settings.show_match_time,
      'show_race_to', v_settings.show_race_to,
      'show_discipline', v_settings.show_discipline,
      'dynamic_interval_seconds', v_settings.dynamic_interval_seconds,
      'dynamic_auto', v_settings.dynamic_auto
    ),
    'tournament', jsonb_build_object(
      'id', v_tournament.id,
      'name', v_tournament.name,
      'sport', v_tournament.sport,
      'discipline', v_tournament.discipline,
      'format', v_tournament.format,
      'status', v_tournament.status,
      'date', v_tournament.date,
      'venue', v_tournament.venue,
      'race_to', nullif(v_tournament.config->>'race_to','')::integer
    ),
    'resources', v_resources,
    'matches', v_matches
  );
end;
$$;

revoke all on function public.get_tournament_display_payload(uuid) from public;
grant execute on function public.get_tournament_display_payload(uuid) to anon, authenticated;
