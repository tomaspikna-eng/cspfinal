begin;

alter table public.tournaments drop constraint if exists tournaments_status_check;
alter table public.tournaments add constraint tournaments_status_check check (status in ('draft','ready','active','completed','archived'));

alter table public.tournament_resources
  add column if not exists operating_mode text not null default 'manual',
  add column if not exists automation_enabled boolean not null default false;

alter table public.tournament_resources drop constraint if exists tournament_resources_operating_mode_check;
alter table public.tournament_resources add constraint tournament_resources_operating_mode_check check (operating_mode in ('smart','manual'));

create table if not exists public.tournament_bracket_states (
  tournament_id uuid primary key references public.tournaments(id) on delete cascade,
  state jsonb not null default '{}'::jsonb,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

alter table public.tournament_bracket_states enable row level security;
drop policy if exists tournament_bracket_states_owner_select on public.tournament_bracket_states;
create policy tournament_bracket_states_owner_select on public.tournament_bracket_states
for select using (exists(select 1 from public.tournaments t where t.id=tournament_id and (t.owner_id=auth.uid() or public.is_admin(auth.uid()))));
drop policy if exists tournament_bracket_states_owner_write on public.tournament_bracket_states;
create policy tournament_bracket_states_owner_write on public.tournament_bracket_states
for all using (exists(select 1 from public.tournaments t where t.id=tournament_id and (t.owner_id=auth.uid() or public.is_admin(auth.uid()))))
with check (exists(select 1 from public.tournaments t where t.id=tournament_id and (t.owner_id=auth.uid() or public.is_admin(auth.uid()))));

create or replace function public.save_tournament_bracket_state(p_tournament_id uuid,p_state jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not exists(select 1 from public.tournaments t where t.id=p_tournament_id and (t.owner_id=auth.uid() or public.is_admin(auth.uid()))) then
    raise exception 'Tournament not found or access denied';
  end if;
  insert into public.tournament_bracket_states(tournament_id,state,updated_by,updated_at)
  values(p_tournament_id,coalesce(p_state,'{}'::jsonb),auth.uid(),now())
  on conflict(tournament_id) do update set state=excluded.state,updated_by=excluded.updated_by,updated_at=now();
  return coalesce(p_state,'{}'::jsonb);
end $$;

create or replace function public.get_tournament_bracket_state(p_tournament_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v jsonb;
begin
  if not exists(select 1 from public.tournaments t where t.id=p_tournament_id and (t.owner_id=auth.uid() or public.is_admin(auth.uid()))) then
    raise exception 'Tournament not found or access denied';
  end if;
  select state into v from public.tournament_bracket_states where tournament_id=p_tournament_id;
  return coalesce(v,'{}'::jsonb);
end $$;

create or replace function public.set_tournament_workflow_status(p_tournament_id uuid,p_status text)
returns public.tournaments language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.tournaments;
begin
  if p_status not in ('draft','ready','active','completed','archived') then raise exception 'Invalid tournament status'; end if;
  select * into v from public.tournaments t where t.id=p_tournament_id and (t.owner_id=auth.uid() or public.is_admin(auth.uid())) for update;
  if v.id is null then raise exception 'Tournament not found or access denied'; end if;
  if p_status='active' and v.status not in ('draft','ready','active') then raise exception 'Tournament cannot be started from current status'; end if;
  if p_status='ready' and v.status not in ('draft','ready') then raise exception 'Only a draft tournament can be marked ready'; end if;
  update public.tournaments set status=p_status,
    started_at=case when p_status='active' then coalesce(started_at,now()) else started_at end,
    completed_at=case when p_status='completed' then coalesce(completed_at,now()) else completed_at end,
    archived_at=case when p_status='archived' then coalesce(archived_at,now()) else archived_at end,
    updated_at=now()
  where id=p_tournament_id returning * into v;
  return v;
end $$;

create or replace function public.sync_draft_tournament_players(p_tournament_id uuid,p_players jsonb)
returns setof public.tournament_players language plpgsql security definer set search_path=public,pg_temp as $$
declare v_status text; item jsonb; n integer:=0;
begin
  select status into v_status from public.tournaments t where t.id=p_tournament_id and (t.owner_id=auth.uid() or public.is_admin(auth.uid())) for update;
  if v_status is null then raise exception 'Tournament not found or access denied'; end if;
  if v_status not in ('draft','ready') or exists(select 1 from public.matches m where m.tournament_id=p_tournament_id) then
    raise exception 'Player list is locked after matches are created or tournament starts';
  end if;
  delete from public.tournament_groups where tournament_id=p_tournament_id;
  delete from public.tournament_players where tournament_id=p_tournament_id;
  for item in select * from jsonb_array_elements(coalesce(p_players,'[]'::jsonb)) loop
    n:=n+1;
    insert into public.tournament_players(tournament_id,name,seed)
    values(p_tournament_id,nullif(trim(item->>'name'),''),coalesce((item->>'seed')::integer,n));
  end loop;
  return query select * from public.tournament_players where tournament_id=p_tournament_id order by seed;
end $$;

create or replace function public.set_tournament_resource_mode(p_resource_id uuid,p_mode text,p_automation_enabled boolean default false)
returns public.tournament_resources language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.tournament_resources;
begin
  if p_mode not in ('smart','manual') then raise exception 'Invalid operating mode'; end if;
  select r.* into v from public.tournament_resources r join public.tournaments t on t.id=r.tournament_id
  where r.id=p_resource_id and (t.owner_id=auth.uid() or public.is_admin(auth.uid())) for update of r;
  if v.id is null then raise exception 'Resource not found or access denied'; end if;
  update public.tournament_resources set operating_mode=p_mode,automation_enabled=coalesce(p_automation_enabled,false),updated_at=now()
  where id=p_resource_id returning * into v;
  return v;
end $$;

create or replace function public.emergency_start_tournament_match(p_match_id uuid)
returns public.matches language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.matches; now_ts timestamptz:=now();
begin
  select m.* into v from public.matches m join public.tournaments t on t.id=m.tournament_id
  where m.id=p_match_id and (t.owner_id=auth.uid() or public.is_admin(auth.uid())) for update of m;
  if v.id is null then raise exception 'Match not found or access denied'; end if;
  if v.status in ('completed','forfeited') then raise exception 'Match is already closed'; end if;
  update public.matches set status='in_progress',started_at=coalesce(started_at,now_ts),match_clock_started_at=coalesce(match_clock_started_at,now_ts),match_clock_paused_at=null,match_clock_stopped_at=null,match_call_status='closed',updated_at=now_ts where id=p_match_id returning * into v;
  if v.tournament_resource_id is not null then update public.tournament_resources set status='in_progress',current_match_id=v.id,updated_at=now_ts where id=v.tournament_resource_id; end if;
  return v;
end $$;

create or replace function public.get_tournament_operations(p_tournament_id uuid)
returns table(resource_id uuid,resource_number integer,resource_label text,resource_type text,resource_status text,operating_mode text,automation_enabled boolean,tablet_name text,tablet_last_seen_at timestamptz,tablet_online boolean,device_token uuid,match_id uuid,round_key text,match_status text,player1_id uuid,player1_name text,player1_present boolean,player2_id uuid,player2_name text,player2_present boolean,both_players_present boolean,started_at timestamptz)
language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not exists(select 1 from public.tournaments t where t.id=p_tournament_id and (t.owner_id=auth.uid() or public.is_admin(auth.uid()))) then raise exception 'Tournament not found or access denied'; end if;
  return query select r.id,r.resource_number,r.label,r.resource_type,r.status,r.operating_mode,r.automation_enabled,r.tablet_name,r.tablet_last_seen_at,(r.tablet_last_seen_at is not null and r.tablet_last_seen_at>now()-interval '20 seconds'),r.device_token,m.id,m.round_key,m.status,m.player1_id,p1.name,(m.player1_ready_at is not null),m.player2_id,p2.name,(m.player2_ready_at is not null),(m.player1_ready_at is not null and m.player2_ready_at is not null),m.started_at
  from public.tournament_resources r
  left join public.matches m on m.id=r.current_match_id
  left join public.tournament_players p1 on p1.id=m.player1_id
  left join public.tournament_players p2 on p2.id=m.player2_id
  where r.tournament_id=p_tournament_id and r.is_active=true order by r.sort_order,r.resource_number;
end $$;

commit;

