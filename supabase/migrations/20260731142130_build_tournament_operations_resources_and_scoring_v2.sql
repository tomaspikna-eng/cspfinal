begin;

create table if not exists public.tournament_resources (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  resource_number integer not null,
  label text not null,
  resource_type text not null default 'table' check (resource_type in ('table','dartboard','lane','court','desk','other')),
  status text not null default 'available' check (status in ('available','assigned','in_progress','paused','maintenance','offline')),
  current_match_id uuid null references public.matches(id) on delete set null,
  device_token uuid not null default gen_random_uuid(),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tournament_id, resource_number),
  unique(device_token)
);

create index if not exists tournament_resources_tournament_status_idx on public.tournament_resources(tournament_id,status,is_active,sort_order,resource_number);
create index if not exists tournament_resources_current_match_idx on public.tournament_resources(current_match_id) where current_match_id is not null;

create table if not exists public.tournament_resource_assignments (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  resource_id uuid not null references public.tournament_resources(id) on delete cascade,
  match_id uuid not null references public.matches(id) on delete cascade,
  assigned_by uuid null references auth.users(id) on delete set null,
  assigned_at timestamptz not null default now(),
  started_at timestamptz null,
  completed_at timestamptz null,
  released_at timestamptz null,
  score1 integer null,
  score2 integer null,
  winner_id uuid null references public.tournament_players(id) on delete set null,
  result_source text null check (result_source in ('organizer','scorer','resource_device','system')),
  created_at timestamptz not null default now()
);
create unique index if not exists tournament_resource_assignments_one_open_per_resource on public.tournament_resource_assignments(resource_id) where released_at is null;
create unique index if not exists tournament_resource_assignments_one_open_per_match on public.tournament_resource_assignments(match_id) where released_at is null;
create index if not exists tournament_resource_assignments_tournament_idx on public.tournament_resource_assignments(tournament_id,assigned_at desc);

create table if not exists public.tournament_scorers (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  name text not null,
  access_token uuid not null default gen_random_uuid(),
  is_active boolean not null default true,
  created_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  last_used_at timestamptz null,
  unique(access_token)
);
create index if not exists tournament_scorers_tournament_idx on public.tournament_scorers(tournament_id,is_active);

alter table public.matches
  add column if not exists tournament_resource_id uuid null,
  add column if not exists tournament_resource_label text null,
  add column if not exists result_source text null,
  add column if not exists result_submitted_at timestamptz null;

alter table public.matches drop constraint if exists matches_tournament_resource_id_fkey;
alter table public.matches add constraint matches_tournament_resource_id_fkey foreign key (tournament_resource_id) references public.tournament_resources(id) on delete set null;
create index if not exists matches_tournament_resource_idx on public.matches(tournament_resource_id) where tournament_resource_id is not null;

alter table public.tournament_resources enable row level security;
alter table public.tournament_resource_assignments enable row level security;
alter table public.tournament_scorers enable row level security;

drop policy if exists tournament_resources_owner_all on public.tournament_resources;
create policy tournament_resources_owner_all on public.tournament_resources for all using (
  exists(select 1 from public.tournaments t where t.id=tournament_id and (t.owner_id=auth.uid() or public.is_admin(auth.uid())))
) with check (
  exists(select 1 from public.tournaments t where t.id=tournament_id and (t.owner_id=auth.uid() or public.is_admin(auth.uid())))
);
drop policy if exists tournament_resources_public_read on public.tournament_resources;
create policy tournament_resources_public_read on public.tournament_resources for select using (
  exists(select 1 from public.tournaments t where t.id=tournament_id and t.status<>'draft')
);

drop policy if exists tournament_resource_assignments_owner_all on public.tournament_resource_assignments;
create policy tournament_resource_assignments_owner_all on public.tournament_resource_assignments for all using (
  exists(select 1 from public.tournaments t where t.id=tournament_id and (t.owner_id=auth.uid() or public.is_admin(auth.uid())))
) with check (
  exists(select 1 from public.tournaments t where t.id=tournament_id and (t.owner_id=auth.uid() or public.is_admin(auth.uid())))
);
drop policy if exists tournament_resource_assignments_public_read on public.tournament_resource_assignments;
create policy tournament_resource_assignments_public_read on public.tournament_resource_assignments for select using (
  exists(select 1 from public.tournaments t where t.id=tournament_id and t.status<>'draft')
);

drop policy if exists tournament_scorers_owner_all on public.tournament_scorers;
create policy tournament_scorers_owner_all on public.tournament_scorers for all using (
  exists(select 1 from public.tournaments t where t.id=tournament_id and (t.owner_id=auth.uid() or public.is_admin(auth.uid())))
) with check (
  exists(select 1 from public.tournaments t where t.id=tournament_id and (t.owner_id=auth.uid() or public.is_admin(auth.uid())))
);

create or replace function public.create_tournament_resources(
  p_tournament_id uuid,
  p_count integer,
  p_resource_type text default 'table',
  p_label_prefix text default null,
  p_start_number integer default 1
) returns setof public.tournament_resources
language plpgsql security definer set search_path='public','pg_temp'
as $$
declare v_owner uuid; v_prefix text; i integer;
begin
  select owner_id into v_owner from public.tournaments where id=p_tournament_id;
  if v_owner is null or not (v_owner=auth.uid() or public.is_admin(auth.uid())) then raise exception 'Tournament not found or access denied'; end if;
  if p_count is null or p_count<1 or p_count>1000 then raise exception 'Resource count must be between 1 and 1000'; end if;
  if p_start_number is null or p_start_number<1 then raise exception 'Start number must be positive'; end if;
  if p_resource_type not in ('table','dartboard','lane','court','desk','other') then raise exception 'Invalid resource type'; end if;
  v_prefix:=coalesce(nullif(trim(p_label_prefix),''),case p_resource_type when 'dartboard' then 'Terč' when 'lane' then 'Dráha' when 'court' then 'Kurt' when 'desk' then 'Zapisovateľský stôl' else 'Stôl' end);
  for i in p_start_number..(p_start_number+p_count-1) loop
    insert into public.tournament_resources(tournament_id,resource_number,label,resource_type,sort_order)
    values(p_tournament_id,i,v_prefix||' '||i,p_resource_type,i)
    on conflict(tournament_id,resource_number) do update set label=excluded.label,resource_type=excluded.resource_type,is_active=true,updated_at=now();
  end loop;
  return query select * from public.tournament_resources where tournament_id=p_tournament_id and resource_number between p_start_number and p_start_number+p_count-1 order by resource_number;
end $$;

create or replace function public.assign_tournament_match(p_resource_id uuid,p_match_id uuid)
returns public.matches language plpgsql security definer set search_path='public','pg_temp'
as $$
declare v_resource public.tournament_resources; v_match public.matches;
begin
  select r.* into v_resource from public.tournament_resources r join public.tournaments t on t.id=r.tournament_id
  where r.id=p_resource_id and r.is_active=true and (t.owner_id=auth.uid() or public.is_admin(auth.uid())) for update of r;
  if v_resource.id is null then raise exception 'Resource not found or access denied'; end if;
  if v_resource.status not in ('available','assigned') or v_resource.current_match_id is not null then raise exception 'Resource is not available'; end if;
  select * into v_match from public.matches where id=p_match_id and tournament_id=v_resource.tournament_id for update;
  if v_match.id is null then raise exception 'Match does not belong to this tournament'; end if;
  if v_match.player1_id is null or v_match.player2_id is null then raise exception 'Match does not have both players'; end if;
  if v_match.status in ('completed','forfeited','cancelled') then raise exception 'Match is already closed'; end if;
  if v_match.tournament_resource_id is not null and v_match.tournament_resource_id<>p_resource_id then raise exception 'Match is already assigned to another resource'; end if;
  update public.tournament_resources set current_match_id=p_match_id,status='assigned',updated_at=now() where id=p_resource_id;
  update public.matches set tournament_resource_id=p_resource_id,tournament_resource_label=v_resource.label,status=case when status in ('pending','waiting_for_table') then 'ready' else status end,updated_at=now() where id=p_match_id returning * into v_match;
  insert into public.tournament_resource_assignments(tournament_id,resource_id,match_id,assigned_by) values(v_resource.tournament_id,p_resource_id,p_match_id,auth.uid());
  return v_match;
end $$;

create or replace function public.get_tournament_resource_match(p_device_token uuid)
returns table(resource_id uuid,tournament_id uuid,resource_number integer,resource_label text,resource_type text,resource_status text,match_id uuid,tournament_name text,discipline text,round_key text,match_number integer,player1_id uuid,player1_name text,player2_id uuid,player2_name text,score1 integer,score2 integer,match_status text)
language sql stable security definer set search_path='public','pg_temp'
as $$
  select r.id,r.tournament_id,r.resource_number,r.label,r.resource_type,r.status,m.id,t.name,t.discipline,m.round_key,m.match_number,m.player1_id,p1.name,m.player2_id,p2.name,coalesce(m.score1,0),coalesce(m.score2,0),m.status
  from public.tournament_resources r join public.tournaments t on t.id=r.tournament_id
  left join public.matches m on m.id=r.current_match_id
  left join public.tournament_players p1 on p1.id=m.player1_id
  left join public.tournament_players p2 on p2.id=m.player2_id
  where r.device_token=p_device_token and r.is_active=true;
$$;

create or replace function public.complete_tournament_match(p_match_id uuid,p_score1 integer,p_score2 integer,p_scorer_token uuid default null,p_resource_token uuid default null)
returns public.matches language plpgsql security definer set search_path='public','pg_temp'
as $$
declare v_match public.matches; v_owner uuid; v_authorized boolean:=false; v_source text; v_resource_id uuid; v_winner uuid; v_elapsed integer;
begin
  if p_score1 is null or p_score2 is null or p_score1<0 or p_score2<0 then raise exception 'Scores must be nonnegative'; end if;
  if p_score1=p_score2 then raise exception 'A completed match cannot end in a tie'; end if;
  select m.* into v_match from public.matches m where m.id=p_match_id for update;
  if v_match.id is null then raise exception 'Match not found'; end if;
  select owner_id into v_owner from public.tournaments where id=v_match.tournament_id;
  if v_match.player1_id is null or v_match.player2_id is null then raise exception 'Match does not have both players'; end if;
  if v_match.status in ('completed','forfeited') then raise exception 'Match is already completed'; end if;
  if auth.uid() is not null and (v_owner=auth.uid() or public.is_admin(auth.uid())) then v_authorized:=true; v_source:='organizer'; end if;
  if not v_authorized and p_scorer_token is not null and exists(select 1 from public.tournament_scorers s where s.access_token=p_scorer_token and s.tournament_id=v_match.tournament_id and s.is_active) then
    v_authorized:=true; v_source:='scorer'; update public.tournament_scorers set last_used_at=now() where access_token=p_scorer_token;
  end if;
  if not v_authorized and p_resource_token is not null then
    select id into v_resource_id from public.tournament_resources where device_token=p_resource_token and tournament_id=v_match.tournament_id and current_match_id=p_match_id and is_active;
    if v_resource_id is not null then v_authorized:=true; v_source:='resource_device'; end if;
  end if;
  if not v_authorized then raise exception 'Access denied'; end if;
  v_winner:=case when p_score1>p_score2 then v_match.player1_id else v_match.player2_id end;
  v_elapsed:=v_match.match_clock_elapsed_seconds + case when v_match.match_clock_started_at is not null then greatest(extract(epoch from(now()-v_match.match_clock_started_at))::integer,0) else 0 end;
  update public.matches set score1=p_score1,score2=p_score2,winner_id=v_winner,status='completed',completed_at=now(),match_call_status='closed',match_clock_elapsed_seconds=v_elapsed,match_clock_started_at=null,match_clock_paused_at=null,match_clock_stopped_at=now(),result_source=v_source,result_submitted_at=now(),updated_at=now() where id=p_match_id returning * into v_match;
  update public.tournament_resource_assignments set completed_at=now(),released_at=now(),score1=p_score1,score2=p_score2,winner_id=v_winner,result_source=v_source where match_id=p_match_id and released_at is null;
  update public.tournament_resources set current_match_id=null,status='available',updated_at=now() where current_match_id=p_match_id;
  update public.matches set tournament_resource_id=null where id=p_match_id;
  return v_match;
end $$;

create or replace function public.suggest_next_tournament_matches(p_tournament_id uuid,p_limit integer default 20)
returns table(match_id uuid,round_key text,round_number integer,match_number integer,player1_id uuid,player1_name text,player2_id uuid,player2_name text,priority integer)
language sql stable security definer set search_path='public','pg_temp'
as $$
  select m.id,m.round_key,m.round_number,m.match_number,m.player1_id,p1.name,m.player2_id,p2.name,row_number() over(order by coalesce(m.round_number,999999),coalesce(m.match_number,999999),m.created_at)::integer
  from public.matches m join public.tournaments t on t.id=m.tournament_id
  left join public.tournament_players p1 on p1.id=m.player1_id left join public.tournament_players p2 on p2.id=m.player2_id
  where m.tournament_id=p_tournament_id and (t.owner_id=auth.uid() or public.is_admin(auth.uid())) and m.player1_id is not null and m.player2_id is not null and m.status in ('pending','waiting_for_table','ready','called','player_arriving') and m.tournament_resource_id is null
  order by coalesce(m.round_number,999999),coalesce(m.match_number,999999),m.created_at limit greatest(1,least(coalesce(p_limit,20),200));
$$;

create or replace function public.assign_next_tournament_match(p_resource_id uuid)
returns public.matches language plpgsql security definer set search_path='public','pg_temp'
as $$
declare v_tid uuid; v_mid uuid; v_match public.matches;
begin
  select r.tournament_id into v_tid from public.tournament_resources r join public.tournaments t on t.id=r.tournament_id where r.id=p_resource_id and r.is_active and r.status='available' and r.current_match_id is null and (t.owner_id=auth.uid() or public.is_admin(auth.uid())) for update of r;
  if v_tid is null then raise exception 'Resource is not available or access denied'; end if;
  select m.id into v_mid from public.matches m where m.tournament_id=v_tid and m.player1_id is not null and m.player2_id is not null and m.status in ('pending','waiting_for_table','ready','called','player_arriving') and m.tournament_resource_id is null order by coalesce(m.round_number,999999),coalesce(m.match_number,999999),m.created_at limit 1 for update skip locked;
  if v_mid is null then raise exception 'No eligible match is waiting'; end if;
  v_match:=public.assign_tournament_match(p_resource_id,v_mid);
  return v_match;
end $$;

create or replace function public.release_tournament_resource(p_resource_id uuid)
returns public.tournament_resources language plpgsql security definer set search_path='public','pg_temp'
as $$
declare v public.tournament_resources;
begin
  select r.* into v from public.tournament_resources r join public.tournaments t on t.id=r.tournament_id where r.id=p_resource_id and (t.owner_id=auth.uid() or public.is_admin(auth.uid())) for update of r;
  if v.id is null then raise exception 'Resource not found or access denied'; end if;
  if v.current_match_id is not null then
    update public.matches set tournament_resource_id=null,tournament_resource_label=coalesce(tournament_resource_label,v.label),updated_at=now() where id=v.current_match_id;
    update public.tournament_resource_assignments set released_at=now() where resource_id=v.id and released_at is null;
  end if;
  update public.tournament_resources set current_match_id=null,status='available',updated_at=now() where id=p_resource_id returning * into v;
  return v;
end $$;

grant execute on function public.create_tournament_resources(uuid,integer,text,text,integer) to authenticated;
grant execute on function public.assign_tournament_match(uuid,uuid) to authenticated;
grant execute on function public.assign_next_tournament_match(uuid) to authenticated;
grant execute on function public.suggest_next_tournament_matches(uuid,integer) to authenticated;
grant execute on function public.release_tournament_resource(uuid) to authenticated;
grant execute on function public.get_tournament_resource_match(uuid) to anon,authenticated;
grant execute on function public.complete_tournament_match(uuid,integer,integer,uuid,uuid) to anon,authenticated;

do $$ begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    begin alter publication supabase_realtime add table public.tournament_resources; exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.tournament_resource_assignments; exception when duplicate_object then null; end;
  end if;
end $$;

commit;

