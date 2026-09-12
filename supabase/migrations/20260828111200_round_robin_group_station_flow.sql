alter table public.matches add column if not exists group_index integer;

update public.matches
set group_index = (substring(round_key from '^grp:([0-9]+):'))::integer + 1
where group_index is null
  and round_key ~ '^grp:[0-9]+:';

alter table public.matches drop constraint if exists matches_group_index_check;
alter table public.matches add constraint matches_group_index_check check (group_index is null or group_index >= 1);

create index if not exists matches_tournament_group_queue_idx
  on public.matches(tournament_id, group_index, round_number, match_number)
  where group_index is not null;

create table if not exists public.tournament_group_resources (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  group_index integer not null check (group_index >= 1),
  resource_id uuid not null references public.tournament_resources(id) on delete cascade,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tournament_id, group_index),
  unique(resource_id)
);

alter table public.tournament_group_resources enable row level security;

drop policy if exists tournament_group_resources_owner_all on public.tournament_group_resources;
create policy tournament_group_resources_owner_all
on public.tournament_group_resources
for all
to authenticated
using (
  exists (
    select 1 from public.tournaments t
    where t.id = tournament_group_resources.tournament_id
      and (t.owner_id = auth.uid() or public.is_admin(auth.uid()))
  )
)
with check (
  exists (
    select 1 from public.tournaments t
    where t.id = tournament_group_resources.tournament_id
      and (t.owner_id = auth.uid() or public.is_admin(auth.uid()))
  )
);

grant select, insert, update, delete on public.tournament_group_resources to authenticated;

create or replace function public.set_tournament_group_resource(
  p_tournament_id uuid,
  p_group_index integer,
  p_resource_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_t public.tournaments;
  v_old public.tournament_group_resources;
  v_resource public.tournament_resources;
  v_old_resource public.tournament_resources;
  v_current public.matches;
begin
  if p_group_index is null or p_group_index < 1 then
    raise exception 'Invalid group index';
  end if;

  select * into v_t
  from public.tournaments
  where id = p_tournament_id
    and (owner_id = auth.uid() or public.is_admin(auth.uid()));

  if v_t.id is null then
    raise exception 'Tournament not found or access denied';
  end if;

  if v_t.format not in ('rr_sko','rr_dko') then
    raise exception 'Group station assignment is available only for Round Robin group phases';
  end if;

  if not exists (
    select 1 from public.tournament_groups g
    where g.tournament_id = p_tournament_id and g.group_index = p_group_index
  ) then
    raise exception 'Tournament group not found';
  end if;

  select * into v_old
  from public.tournament_group_resources
  where tournament_id = p_tournament_id and group_index = p_group_index
  for update;

  if v_old.id is not null and (p_resource_id is null or v_old.resource_id <> p_resource_id) then
    select * into v_old_resource
    from public.tournament_resources
    where id = v_old.resource_id
    for update;

    if v_old_resource.current_match_id is not null then
      select * into v_current from public.matches where id = v_old_resource.current_match_id;
      if v_current.group_index = p_group_index and v_current.status in ('live','in_progress') then
        raise exception 'Cannot change group station while its match is live';
      end if;
      if v_current.group_index = p_group_index then
        update public.matches
        set tournament_resource_id = null,
            tournament_resource_label = coalesce(tournament_resource_label, v_old_resource.label),
            updated_at = now()
        where id = v_old_resource.current_match_id;

        update public.tournament_resource_assignments
        set released_at = coalesce(released_at, now())
        where resource_id = v_old_resource.id and released_at is null;

        update public.tournament_resources
        set current_match_id = null, status = 'available', updated_at = now()
        where id = v_old_resource.id;
      end if;
    end if;
  end if;

  if p_resource_id is null then
    delete from public.tournament_group_resources
    where tournament_id = p_tournament_id and group_index = p_group_index;
    return jsonb_build_object('group_index',p_group_index,'resource_id',null);
  end if;

  select * into v_resource
  from public.tournament_resources
  where id = p_resource_id
    and tournament_id = p_tournament_id
    and is_active = true
  for update;

  if v_resource.id is null then
    raise exception 'Tournament resource not found';
  end if;

  if exists (
    select 1 from public.tournament_group_resources x
    where x.resource_id = p_resource_id
      and not (x.tournament_id = p_tournament_id and x.group_index = p_group_index)
  ) then
    raise exception 'This station is already assigned to another group';
  end if;

  insert into public.tournament_group_resources(tournament_id,group_index,resource_id,created_by,updated_at)
  values(p_tournament_id,p_group_index,p_resource_id,auth.uid(),now())
  on conflict(tournament_id,group_index)
  do update set resource_id = excluded.resource_id, updated_at = now();

  return jsonb_build_object('group_index',p_group_index,'resource_id',p_resource_id);
end;
$$;

grant execute on function public.set_tournament_group_resource(uuid,integer,uuid) to authenticated;

create or replace function public.remove_tournament_resource(p_resource_id uuid)
returns public.tournament_resources
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v public.tournament_resources;
  v_match public.matches;
begin
  select r.* into v
  from public.tournament_resources r
  join public.tournaments t on t.id = r.tournament_id
  where r.id = p_resource_id
    and (t.owner_id = auth.uid() or public.is_admin(auth.uid()))
  for update of r;

  if v.id is null then
    raise exception 'Resource not found or access denied';
  end if;

  if v.current_match_id is not null then
    select * into v_match from public.matches where id = v.current_match_id for update;
    if v_match.status in ('live','in_progress') then
      raise exception 'Cannot remove a station while a match is live';
    end if;

    update public.matches
    set tournament_resource_id = null,
        tournament_resource_label = coalesce(tournament_resource_label, v.label),
        updated_at = now()
    where id = v.current_match_id;

    update public.tournament_resource_assignments
    set released_at = coalesce(released_at, now())
    where resource_id = v.id and released_at is null;
  end if;

  delete from public.tournament_group_resources where resource_id = v.id;

  update public.tournament_resources
  set current_match_id = null,
      status = 'available',
      is_active = false,
      updated_at = now()
  where id = v.id
  returning * into v;

  return v;
end;
$$;

grant execute on function public.remove_tournament_resource(uuid) to authenticated;

create or replace function public.advance_round_robin_group_station()
returns trigger
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_map public.tournament_group_resources;
  v_resource public.tournament_resources;
  v_next public.matches;
  v_used_resource uuid;
  v_after_current boolean;
begin
  if new.group_index is null then return new; end if;
  if new.status not in ('completed','forfeited') then return new; end if;
  if old.status in ('completed','forfeited') then return new; end if;

  select * into v_map
  from public.tournament_group_resources
  where tournament_id = new.tournament_id and group_index = new.group_index;

  if v_map.id is null then return new; end if;

  v_used_resource := coalesce(new.tournament_resource_id, old.tournament_resource_id);
  if v_used_resource is distinct from v_map.resource_id then return new; end if;

  select * into v_resource
  from public.tournament_resources
  where id = v_map.resource_id and is_active = true
  for update;

  if v_resource.id is null then return new; end if;
  if v_resource.current_match_id is not null and v_resource.current_match_id <> new.id then return new; end if;

  select m.* into v_next
  from public.matches m
  where m.tournament_id = new.tournament_id
    and m.group_index = new.group_index
    and m.id <> new.id
    and m.player1_id is not null
    and m.player2_id is not null
    and m.status not in ('completed','forfeited')
  order by
    case
      when coalesce(m.round_number,2147483647) > coalesce(new.round_number,2147483647)
        or (coalesce(m.round_number,2147483647) = coalesce(new.round_number,2147483647)
            and coalesce(m.match_number,2147483647) > coalesce(new.match_number,2147483647))
      then 0 else 1
    end,
    m.round_number nulls last,
    m.match_number nulls last,
    m.created_at
  limit 1
  for update;

  if v_next.id is null then return new; end if;

  update public.tournament_resources
  set current_match_id = v_next.id,
      status = 'assigned',
      updated_at = now()
  where id = v_resource.id;

  update public.matches
  set tournament_resource_id = v_resource.id,
      tournament_resource_label = v_resource.label,
      player1_ready_at = null,
      player2_ready_at = null,
      status = case when status in ('pending','waiting_for_table') then 'ready' else status end,
      match_call_status = 'not_called',
      called_at = null,
      arrival_deadline_at = null,
      penalty_1_at = null,
      penalty_2_at = null,
      penalty_3_at = null,
      forfeit_at = null,
      updated_at = now()
  where id = v_next.id;

  insert into public.tournament_resource_assignments(tournament_id,resource_id,match_id,assigned_by,result_source)
  values(new.tournament_id,v_resource.id,v_next.id,auth.uid(),'system');

  return new;
end;
$$;

drop trigger if exists matches_advance_round_robin_group_station on public.matches;
create trigger matches_advance_round_robin_group_station
after update of status on public.matches
for each row
when (new.status in ('completed','forfeited'))
execute function public.advance_round_robin_group_station();

