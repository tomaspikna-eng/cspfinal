create table if not exists public.phase_qualifiers (
 id uuid primary key default gen_random_uuid(), phase_id uuid not null references public.tournament_phases(id) on delete cascade,
 tournament_player_id uuid not null references public.tournament_players(id) on delete cascade,
 qualification_position integer not null, seed integer, source_group integer, metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(), unique(phase_id,tournament_player_id), unique(phase_id,qualification_position),
 check(qualification_position>0), check(seed is null or seed>0)
);
alter table public.phase_qualifiers enable row level security;
create policy phase_qualifiers_select on public.phase_qualifiers for select to anon,authenticated using(exists(select 1 from public.tournament_phases p join public.tournaments t on t.id=p.tournament_id where p.id=phase_id and (t.owner_id=(select auth.uid()) or t.status<>'draft')));
create policy phase_qualifiers_owner_write on public.phase_qualifiers for all to authenticated using(exists(select 1 from public.tournament_phases p join public.tournaments t on t.id=p.tournament_id where p.id=phase_id and t.owner_id=(select auth.uid()))) with check(exists(select 1 from public.tournament_phases p join public.tournaments t on t.id=p.tournament_id where p.id=phase_id and t.owner_id=(select auth.uid())));
create index if not exists phase_qualifiers_phase_seed_idx on public.phase_qualifiers(phase_id,seed,qualification_position);

alter table public.matches add column if not exists shot_clock_started_at timestamptz, add column if not exists shot_clock_paused_at timestamptz, add column if not exists shot_clock_remaining_seconds integer, add column if not exists shot_clock_current_player_id uuid;
do $$ begin if not exists(select 1 from pg_constraint where conname='matches_shot_clock_current_player_id_fkey') then alter table public.matches add constraint matches_shot_clock_current_player_id_fkey foreign key(shot_clock_current_player_id) references public.tournament_players(id) on delete set null; end if; end $$;
alter table public.matches add constraint matches_shot_clock_remaining_check check(shot_clock_remaining_seconds is null or shot_clock_remaining_seconds>=0);

create or replace function public.complete_round_robin_phase(p_phase_id uuid,p_qualifiers jsonb,p_next_phase_type text)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare ph public.tournament_phases; next_id uuid; q jsonb; next_num int;
begin
 select p.* into ph from public.tournament_phases p join public.tournaments t on t.id=p.tournament_id where p.id=p_phase_id and (t.owner_id=auth.uid() or public.is_admin(auth.uid())) for update of p;
 if ph.id is null then raise exception 'Phase not found or access denied'; end if;
 if ph.phase_type<>'round_robin' then raise exception 'Phase is not round robin'; end if;
 if p_next_phase_type not in('single_elimination','double_elimination') then raise exception 'Invalid next phase type'; end if;
 if exists(select 1 from public.matches where phase_id=p_phase_id and status not in('completed','forfeited')) then raise exception 'Phase contains unfinished matches'; end if;
 delete from public.phase_qualifiers where phase_id=p_phase_id;
 for q in select * from jsonb_array_elements(coalesce(p_qualifiers,'[]'::jsonb)) loop
  if not exists(select 1 from public.tournament_players where id=(q->>'tournament_player_id')::uuid and tournament_id=ph.tournament_id) then raise exception 'Invalid qualifier'; end if;
  insert into public.phase_qualifiers(phase_id,tournament_player_id,qualification_position,seed,source_group,metadata)
  values(p_phase_id,(q->>'tournament_player_id')::uuid,(q->>'qualification_position')::int,nullif(q->>'seed','')::int,nullif(q->>'source_group','')::int,coalesce(q->'metadata','{}'::jsonb));
 end loop;
 update public.tournament_phases set status='completed',completed_at=now() where id=p_phase_id;
 select coalesce(max(phase_number),0)+1 into next_num from public.tournament_phases where tournament_id=ph.tournament_id;
 insert into public.tournament_phases(tournament_id,phase_number,phase_type,status,config) values(ph.tournament_id,next_num,p_next_phase_type,'draft',jsonb_build_object('source_phase_id',p_phase_id)) returning id into next_id;
 update public.tournaments set current_phase_id=next_id where id=ph.tournament_id;
 insert into public.audit_logs(user_id,entity_type,entity_id,action,metadata) values(auth.uid(),'tournament_phase',p_phase_id,'completed',jsonb_build_object('next_phase_id',next_id,'next_phase_type',p_next_phase_type));
 return next_id;
end $$;

create or replace function public.start_shot_clock(p_match_id uuid,p_player_id uuid default null,p_post_break boolean default false)
returns public.matches language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.matches; secs int;
begin
 select m.* into v from public.matches m join public.tournaments t on t.id=m.tournament_id where m.id=p_match_id and (t.owner_id=auth.uid() or m.shot_clock_operator_id=auth.uid() or public.is_admin(auth.uid())) for update of m;
 if v.id is null or not v.shot_clock_enabled then raise exception 'Shot clock unavailable or access denied'; end if;
 if p_player_id is not null and p_player_id is distinct from v.player1_id and p_player_id is distinct from v.player2_id then raise exception 'Player is not in this match'; end if;
 secs:=case when p_post_break then v.post_break_seconds else v.shot_clock_seconds end;
 update public.matches set shot_clock_started_at=now(),shot_clock_paused_at=null,shot_clock_remaining_seconds=secs,shot_clock_current_player_id=p_player_id where id=p_match_id returning * into v;
 return v;
end $$;

create or replace function public.pause_shot_clock(p_match_id uuid)
returns public.matches language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.matches; rem int;
begin
 select m.* into v from public.matches m join public.tournaments t on t.id=m.tournament_id where m.id=p_match_id and (t.owner_id=auth.uid() or m.shot_clock_operator_id=auth.uid() or public.is_admin(auth.uid())) for update of m;
 if v.id is null or v.shot_clock_started_at is null then raise exception 'Running shot clock not found'; end if;
 rem:=greatest(coalesce(v.shot_clock_remaining_seconds,v.shot_clock_seconds)-extract(epoch from(now()-v.shot_clock_started_at))::int,0);
 update public.matches set shot_clock_remaining_seconds=rem,shot_clock_started_at=null,shot_clock_paused_at=now() where id=p_match_id returning * into v;
 return v;
end $$;

create or replace function public.use_shot_clock_extension(p_match_id uuid,p_player_id uuid)
returns public.matches language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.matches; used int;
begin
 select m.* into v from public.matches m join public.tournaments t on t.id=m.tournament_id where m.id=p_match_id and (t.owner_id=auth.uid() or m.shot_clock_operator_id=auth.uid() or public.is_admin(auth.uid())) for update of m;
 if v.id is null then raise exception 'Match not found or access denied'; end if;
 if p_player_id=v.player1_id then used:=v.extensions_used_player1; elsif p_player_id=v.player2_id then used:=v.extensions_used_player2; else raise exception 'Player is not in this match'; end if;
 if used>=v.extensions_allowed then raise exception 'No extensions remaining'; end if;
 update public.matches set shot_clock_remaining_seconds=coalesce(shot_clock_remaining_seconds,shot_clock_seconds)+extension_seconds,
 extensions_used_player1=case when p_player_id=player1_id then extensions_used_player1+1 else extensions_used_player1 end,
 extensions_used_player2=case when p_player_id=player2_id then extensions_used_player2+1 else extensions_used_player2 end
 where id=p_match_id returning * into v;
 return v;
end $$;

create or replace view public.player_match_cards with(security_invoker=true) as
select m.id as match_id,m.tournament_id,t.name as tournament_name,t.discipline,t.format,m.round_key,m.round_number,m.match_number,m.status,m.station_id,s.name as station_name,
 m.player1_id,p1.name as player1_name,p1.user_id as player1_user_id,m.player2_id,p2.name as player2_name,p2.user_id as player2_user_id,
 m.score1,m.score2,m.winner_id,m.called_at,m.arrival_deadline_at,m.penalty_1_at,m.penalty_2_at,m.penalty_3_at,m.forfeit_at,m.match_call_status,
 m.player1_ready_at,m.player2_ready_at,m.shot_clock_enabled,m.shot_clock_seconds,m.post_break_seconds,m.extensions_allowed,m.extensions_used_player1,m.extensions_used_player2,
 m.shot_clock_started_at,m.shot_clock_remaining_seconds,m.shot_clock_current_player_id,
 case when p1.user_id=(select auth.uid()) then p2.name when p2.user_id=(select auth.uid()) then p1.name else null end as opponent_name,
 case when p1.user_id=(select auth.uid()) then m.player1_ready_at when p2.user_id=(select auth.uid()) then m.player2_ready_at else null end as my_ready_at
from public.matches m join public.tournaments t on t.id=m.tournament_id
left join public.tournament_players p1 on p1.id=m.player1_id left join public.tournament_players p2 on p2.id=m.player2_id left join public.stations s on s.id=m.station_id;

create or replace view public.user_tournament_history with(security_invoker=true) as
select tr.user_id,tr.tournament_id,t.name,t.sport,t.discipline,t.format,t.date,t.venue,t.status,tr.final_position,tr.matches_played,tr.wins,tr.losses,tr.score_for,tr.score_against,t.completed_at,t.archived_at
from public.tournament_results tr join public.tournaments t on t.id=tr.tournament_id where tr.user_id is not null;

create or replace view public.user_sport_statistics with(security_invoker=true) as
select tr.user_id,t.sport,t.discipline,count(*)::int as tournaments_played,sum(tr.matches_played)::int as matches_played,sum(tr.wins)::int as wins,sum(tr.losses)::int as losses,
 case when sum(tr.matches_played)>0 then round(100.0*sum(tr.wins)/sum(tr.matches_played),2) else 0 end as win_rate,
 count(*) filter(where tr.final_position=1)::int as tournament_wins
from public.tournament_results tr join public.tournaments t on t.id=tr.tournament_id where tr.user_id is not null group by tr.user_id,t.sport,t.discipline;

create or replace view public.tournament_payment_summary with(security_invoker=true) as
select tournament_id,count(*)::int as players_with_payment,sum(entry_fee_amount) as expected_amount,sum(entry_fee_amount) filter(where payment_status='paid') as paid_amount,
 sum(entry_fee_amount) filter(where payment_status='unpaid') as unpaid_amount,count(*) filter(where payment_status='waived')::int as waived_count,count(*) filter(where payment_status='refunded')::int as refunded_count,currency
from public.tournament_player_payments group by tournament_id,currency;

revoke execute on function public.complete_round_robin_phase(uuid,jsonb,text),public.start_shot_clock(uuid,uuid,boolean),public.pause_shot_clock(uuid),public.use_shot_clock_extension(uuid,uuid) from public,anon;
grant execute on function public.complete_round_robin_phase(uuid,jsonb,text),public.start_shot_clock(uuid,uuid,boolean),public.pause_shot_clock(uuid),public.use_shot_clock_extension(uuid,uuid) to authenticated;
grant select on public.player_match_cards,public.user_tournament_history,public.user_sport_statistics,public.tournament_payment_summary to authenticated;
grant select on public.player_match_cards to anon;

