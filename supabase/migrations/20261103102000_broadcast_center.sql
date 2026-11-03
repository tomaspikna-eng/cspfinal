create table if not exists public.broadcast_outputs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  name text not null default 'Broadcast',
  source_type text not null check (source_type in ('tournament_match','team_meeting')),
  source_id uuid not null,
  public_token uuid not null default gen_random_uuid() unique,
  is_active boolean not null default true,
  config jsonb not null default '{"layout":"lower-third","accent":"gold","show_competition":true,"show_meta":true}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists broadcast_outputs_owner_idx
  on public.broadcast_outputs(owner_id, created_at desc);
create index if not exists broadcast_outputs_token_idx
  on public.broadcast_outputs(public_token)
  where is_active = true;

alter table public.broadcast_outputs enable row level security;

drop policy if exists broadcast_outputs_owner_select on public.broadcast_outputs;
create policy broadcast_outputs_owner_select
on public.broadcast_outputs for select to authenticated
using ((select auth.uid()) = owner_id);

drop policy if exists broadcast_outputs_owner_insert on public.broadcast_outputs;
create policy broadcast_outputs_owner_insert
on public.broadcast_outputs for insert to authenticated
with check ((select auth.uid()) = owner_id);

drop policy if exists broadcast_outputs_owner_update on public.broadcast_outputs;
create policy broadcast_outputs_owner_update
on public.broadcast_outputs for update to authenticated
using ((select auth.uid()) = owner_id)
with check ((select auth.uid()) = owner_id);

drop policy if exists broadcast_outputs_owner_delete on public.broadcast_outputs;
create policy broadcast_outputs_owner_delete
on public.broadcast_outputs for delete to authenticated
using ((select auth.uid()) = owner_id);

revoke all on table public.broadcast_outputs from anon, public;
grant select, insert, update, delete on table public.broadcast_outputs to authenticated;

create or replace function public.get_broadcast_payload(p_token uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  b public.broadcast_outputs%rowtype;
  payload jsonb;
begin
  if p_token is null then return null; end if;

  select * into b
  from public.broadcast_outputs
  where public_token = p_token and is_active = true
  limit 1;

  if not found then return null; end if;

  if b.source_type = 'tournament_match' then
    select jsonb_build_object(
      'type','tournament_match',
      'output_id',b.id,
      'output_name',b.name,
      'config',b.config,
      'server_now',now(),
      'competition',jsonb_build_object(
        'id',t.id,'name',t.name,'sport',t.sport,'discipline',t.discipline,
        'date',t.date,'venue',t.venue,'status',t.status
      ),
      'match',jsonb_build_object(
        'id',m.id,'status',m.status,'round_key',m.round_key,'round_number',m.round_number,
        'match_number',m.match_number,'station',coalesce(m.tournament_resource_label,m.station_label),
        'race_to',m.race_to,'home_name',coalesce(p1.name,'—'),'away_name',coalesce(p2.name,'—'),
        'home_score',coalesce(m.score1,0),'away_score',coalesce(m.score2,0),
        'started_at',m.started_at,'completed_at',m.completed_at,
        'match_clock_elapsed_seconds',coalesce(m.match_clock_elapsed_seconds,0),
        'match_clock_started_at',m.match_clock_started_at,'match_clock_paused_at',m.match_clock_paused_at
      )
    ) into payload
    from public.matches m
    join public.tournaments t on t.id=m.tournament_id
    left join public.tournament_players p1 on p1.id=m.player1_id
    left join public.tournament_players p2 on p2.id=m.player2_id
    where m.id=b.source_id and t.owner_id=b.owner_id;
    return payload;
  end if;

  if b.source_type = 'team_meeting' then
    select jsonb_build_object(
      'type','team_meeting',
      'output_id',b.id,'output_name',b.name,'config',b.config,'server_now',now(),
      'competition',jsonb_build_object(
        'id',c.id,'name',c.name,'sport',c.sport,'season',c.season_name,'status',c.status
      ),
      'meeting',jsonb_build_object(
        'id',m.id,'round_label',m.round_label,'status',m.status,
        'home_team',ht.name,'home_short',ht.short_name,'home_logo',ht.logo_url,'home_score',coalesce(m.home_score,0),
        'away_team',at.name,'away_short',at.short_name,'away_logo',at.logo_url,'away_score',coalesce(m.away_score,0),
        'best_of',m.best_of
      ),
      'current_game',case when cg.id is null then null else jsonb_build_object(
        'id',cg.id,'slot_no',cg.slot_no,'game_type',cg.game_type,'status',cg.status,
        'discipline',cg.discipline,'race_to',cg.race_to,'home_name',cg.home_name,'away_name',cg.away_name,
        'home_score',coalesce(cg.home_score,0),'away_score',coalesce(cg.away_score,0)
      ) end
    ) into payload
    from public.team_meetings m
    join public.team_competitions c on c.id=m.competition_id
    join public.teams ht on ht.id=m.home_team_id
    join public.teams at on at.id=m.away_team_id
    left join lateral (
      select g.id,g.slot_no,g.game_type,g.status,g.discipline,g.race_to,g.home_score,g.away_score,
        case when g.game_type='doubles' then concat_ws(' / ',hm.display_name,hm2.display_name)
             else coalesce(hm.display_name,'—') end as home_name,
        case when g.game_type='doubles' then concat_ws(' / ',am.display_name,am2.display_name)
             else coalesce(am.display_name,'—') end as away_name
      from public.team_match_games g
      left join public.team_members hm on hm.id=g.home_member_id
      left join public.team_members hm2 on hm2.id=g.home_member2_id
      left join public.team_members am on am.id=g.away_member_id
      left join public.team_members am2 on am2.id=g.away_member2_id
      where g.meeting_id=m.id and g.status <> 'cancelled'
      order by case g.status when 'active' then 0 when 'scheduled' then 1 when 'completed' then 2 else 3 end,
               case when g.status='completed' then -g.slot_no else g.slot_no end
      limit 1
    ) cg on true
    where m.id=b.source_id and c.owner_id=b.owner_id;
    return payload;
  end if;

  return null;
end;
$$;

revoke all on function public.get_broadcast_payload(uuid) from public, anon, authenticated;
grant execute on function public.get_broadcast_payload(uuid) to anon, authenticated;

comment on table public.broadcast_outputs is
'CSP Broadcast Center outputs. Browser-source access is via a high-entropy public_token, not direct anonymous table access.';

comment on function public.get_broadcast_payload(uuid) is
'Intentional public read-only broadcast endpoint. Returns only stream-safe score/competition fields for an active unguessable token and verifies source ownership.';
