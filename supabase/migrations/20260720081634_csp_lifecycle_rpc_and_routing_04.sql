alter table public.training_sessions alter column final_score set default '{}'::jsonb;

create or replace function public.start_training_session(p_session_id uuid)
returns public.training_sessions language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.training_sessions;
begin
 update public.training_sessions set status='active',started_at=coalesce(started_at,now()),paused_at=null
 where id=p_session_id and owner_id=auth.uid() and status in('draft','paused') returning * into v;
 if v.id is null then raise exception 'Training session not found or cannot be started'; end if;
 return v;
end $$;

create or replace function public.pause_training_session(p_session_id uuid)
returns public.training_sessions language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.training_sessions;
begin
 update public.training_sessions set elapsed_seconds=elapsed_seconds+greatest(extract(epoch from(now()-started_at))::int,0),paused_at=now(),started_at=null,status='paused'
 where id=p_session_id and owner_id=auth.uid() and status='active' returning * into v;
 if v.id is null then raise exception 'Active training session not found'; end if;
 return v;
end $$;

create or replace function public.complete_training_session(p_session_id uuid,p_final_score jsonb default null,p_winner_name text default null)
returns public.training_sessions language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.training_sessions; d int;
begin
 select * into v from public.training_sessions where id=p_session_id and owner_id=auth.uid() for update;
 if v.id is null then raise exception 'Training session not found'; end if;
 d:=v.elapsed_seconds+case when v.status='active' and v.started_at is not null then greatest(extract(epoch from(now()-v.started_at))::int,0) else 0 end;
 update public.training_sessions set status='completed',final_score=coalesce(p_final_score,final_score),winner_name=coalesce(p_winner_name,winner_name),duration_seconds=d,elapsed_seconds=d,completed_at=now(),played_at=coalesce(played_at,now()),started_at=null,paused_at=null where id=p_session_id returning * into v;
 insert into public.audit_logs(user_id,entity_type,entity_id,action,metadata) values(auth.uid(),'training_session',p_session_id,'completed',jsonb_build_object('duration_seconds',d));
 return v;
end $$;

create or replace function public.call_match(p_match_id uuid)
returns public.matches language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.matches; cfg jsonb; grace int; p1m int; p2m int; p3m int; fm int;
begin
 select m.* into v from public.matches m join public.tournaments t on t.id=m.tournament_id where m.id=p_match_id and t.owner_id=auth.uid() for update of m;
 if v.id is null then raise exception 'Match not found or access denied'; end if;
 select t.config into cfg from public.tournaments t where t.id=v.tournament_id;
 grace:=coalesce((cfg->>'arrival_grace_minutes')::int,5); p1m:=coalesce((cfg->>'penalty_1_minutes')::int,6); p2m:=coalesce((cfg->>'penalty_2_minutes')::int,11); p3m:=coalesce((cfg->>'penalty_3_minutes')::int,16); fm:=coalesce((cfg->>'forfeit_minutes')::int,20);
 if not(grace<=p1m and p1m<=p2m and p2m<=p3m and p3m<=fm) then raise exception 'Invalid arrival penalty configuration'; end if;
 update public.matches set status='called',match_call_status='called',called_at=now(),arrival_deadline_at=now()+make_interval(mins=>grace),penalty_1_at=now()+make_interval(mins=>p1m),penalty_2_at=now()+make_interval(mins=>p2m),penalty_3_at=now()+make_interval(mins=>p3m),forfeit_at=now()+make_interval(mins=>fm) where id=p_match_id returning * into v;
 insert into public.audit_logs(user_id,entity_type,entity_id,action) values(auth.uid(),'match',p_match_id,'called');
 return v;
end $$;

create or replace function public.get_match_arrival_status(p_match_id uuid)
returns table(match_id uuid,seconds_remaining integer,penalty_level integer,penalty_score integer,forfeit_available boolean,call_status text)
language sql stable security definer set search_path=public,pg_temp as $$
 select m.id,
 case when m.called_at is null then null else greatest(extract(epoch from(coalesce(m.forfeit_at,now())-now()))::int,0) end,
 case when m.called_at is null then 0 when now()>=m.forfeit_at then 4 when now()>=m.penalty_3_at then 3 when now()>=m.penalty_2_at then 2 when now()>=m.penalty_1_at then 1 else 0 end,
 case when m.called_at is null then 0 when now()>=m.penalty_3_at then 3 when now()>=m.penalty_2_at then 2 when now()>=m.penalty_1_at then 1 else 0 end,
 (m.forfeit_at is not null and now()>=m.forfeit_at),
 case when m.called_at is null then 'not_called' when now()>=m.forfeit_at then 'forfeit_available' when now()>=m.penalty_3_at then 'penalty_3' when now()>=m.penalty_2_at then 'penalty_2' when now()>=m.penalty_1_at then 'penalty_1' when now()>=m.arrival_deadline_at then 'arrival_window' else 'called' end
 from public.matches m join public.tournaments t on t.id=m.tournament_id
 where m.id=p_match_id and (t.owner_id=auth.uid() or t.status<>'draft' or exists(select 1 from public.tournament_players tp where tp.user_id=auth.uid() and tp.id in(m.player1_id,m.player2_id)));
$$;

create or replace function public.set_match_ready(p_match_id uuid)
returns public.matches language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.matches; p1u uuid; p2u uuid;
begin
 select * into v from public.matches where id=p_match_id for update;
 if v.id is null then raise exception 'Match not found'; end if;
 select user_id into p1u from public.tournament_players where id=v.player1_id;
 select user_id into p2u from public.tournament_players where id=v.player2_id;
 if auth.uid()=p1u then update public.matches set player1_ready_at=now() where id=p_match_id returning * into v;
 elsif auth.uid()=p2u then update public.matches set player2_ready_at=now() where id=p_match_id returning * into v;
 else raise exception 'User is not a participant in this match'; end if;
 if v.player1_ready_at is not null and v.player2_ready_at is not null and v.status in('pending','waiting_for_table','called','player_arriving') then update public.matches set status='ready' where id=p_match_id returning * into v; end if;
 return v;
end $$;

create or replace function public.forfeit_match(p_match_id uuid,p_late_player_id uuid,p_reason text default null)
returns public.matches language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.matches; w uuid;
begin
 select m.* into v from public.matches m join public.tournaments t on t.id=m.tournament_id where m.id=p_match_id and (t.owner_id=auth.uid() or public.is_admin(auth.uid())) for update of m;
 if v.id is null then raise exception 'Match not found or access denied'; end if;
 if p_late_player_id is distinct from v.player1_id and p_late_player_id is distinct from v.player2_id then raise exception 'Late player is not in this match'; end if;
 w:=case when p_late_player_id=v.player1_id then v.player2_id else v.player1_id end;
 if w is null then raise exception 'Cannot forfeit match without an opponent'; end if;
 update public.matches set status='forfeited',winner_id=w,late_player_id=p_late_player_id,forfeit_reason=p_reason,match_call_status='closed',completed_at=now() where id=p_match_id returning * into v;
 insert into public.audit_logs(user_id,entity_type,entity_id,action,metadata) values(auth.uid(),'match',p_match_id,'forfeited',jsonb_build_object('late_player_id',p_late_player_id,'reason',p_reason));
 return v;
end $$;

create or replace function public.complete_tournament(p_tournament_id uuid,p_results jsonb default '[]'::jsonb)
returns public.tournaments language plpgsql security definer set search_path=public,pg_temp as $$
declare t public.tournaments; r jsonb;
begin
 select * into t from public.tournaments where id=p_tournament_id and (owner_id=auth.uid() or public.is_admin(auth.uid())) for update;
 if t.id is null then raise exception 'Tournament not found or access denied'; end if;
 if exists(select 1 from public.matches where tournament_id=p_tournament_id and status not in('completed','forfeited')) then raise exception 'Tournament contains unfinished matches'; end if;
 insert into public.tournament_results(tournament_id,tournament_player_id,user_id,matches_played,wins,losses,score_for,score_against)
 select p_tournament_id,tp.id,tp.user_id,count(m.id)::int,count(m.id) filter(where m.winner_id=tp.id)::int,count(m.id) filter(where m.id is not null and m.winner_id is distinct from tp.id)::int,
 coalesce(sum(case when m.player1_id=tp.id then coalesce(m.score1,0) when m.player2_id=tp.id then coalesce(m.score2,0) else 0 end),0)::int,
 coalesce(sum(case when m.player1_id=tp.id then coalesce(m.score2,0) when m.player2_id=tp.id then coalesce(m.score1,0) else 0 end),0)::int
 from public.tournament_players tp left join public.matches m on m.tournament_id=p_tournament_id and (m.player1_id=tp.id or m.player2_id=tp.id) and m.status in('completed','forfeited') where tp.tournament_id=p_tournament_id group by tp.id,tp.user_id
 on conflict(tournament_id,tournament_player_id) do update set user_id=excluded.user_id,matches_played=excluded.matches_played,wins=excluded.wins,losses=excluded.losses,score_for=excluded.score_for,score_against=excluded.score_against;
 for r in select * from jsonb_array_elements(coalesce(p_results,'[]'::jsonb)) loop
  if not exists(select 1 from public.tournament_players where id=(r->>'tournament_player_id')::uuid and tournament_id=p_tournament_id) then raise exception 'Invalid tournament_player_id in results'; end if;
  update public.tournament_results set final_position=(r->>'final_position')::int,metadata=coalesce(r->'metadata','{}'::jsonb) where tournament_id=p_tournament_id and tournament_player_id=(r->>'tournament_player_id')::uuid;
 end loop;
 update public.tournaments set status='completed',completed_at=now() where id=p_tournament_id returning * into t;
 insert into public.audit_logs(user_id,entity_type,entity_id,action) values(auth.uid(),'tournament',p_tournament_id,'completed');
 return t;
end $$;

create or replace function public.archive_tournament(p_tournament_id uuid)
returns public.tournaments language plpgsql security definer set search_path=public,pg_temp as $$
declare t public.tournaments;
begin
 update public.tournaments set status='archived',archived_at=now() where id=p_tournament_id and (owner_id=auth.uid() or public.is_admin(auth.uid())) and status='completed' returning * into t;
 if t.id is null then raise exception 'Completed tournament not found or access denied'; end if;
 insert into public.audit_logs(user_id,entity_type,entity_id,action) values(auth.uid(),'tournament',p_tournament_id,'archived'); return t;
end $$;

create or replace function public.propagate_match_result()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare loser uuid;
begin
 if new.status not in('completed','forfeited') or new.winner_id is null then return new; end if;
 loser:=case when new.winner_id=new.player1_id then new.player2_id else new.player1_id end;
 if new.next_match_id is not null then
  update public.matches set player1_id=case when player1_id is null then new.winner_id else player1_id end,player2_id=case when player1_id is not null and player2_id is null and player1_id is distinct from new.winner_id then new.winner_id else player2_id end where id=new.next_match_id and new.winner_id is distinct from player1_id and new.winner_id is distinct from player2_id;
 end if;
 if new.loser_next_match_id is not null and loser is not null then
  update public.matches set player1_id=case when player1_id is null then loser else player1_id end,player2_id=case when player1_id is not null and player2_id is null and player1_id is distinct from loser then loser else player2_id end where id=new.loser_next_match_id and loser is distinct from player1_id and loser is distinct from player2_id;
 end if;
 return new;
end $$;

drop trigger if exists matches_propagate_result on public.matches;
create trigger matches_propagate_result after update of status,winner_id on public.matches for each row when(new.status in('completed','forfeited') and new.winner_id is not null) execute function public.propagate_match_result();

revoke execute on function public.start_training_session(uuid) from public,anon;
revoke execute on function public.pause_training_session(uuid) from public,anon;
revoke execute on function public.complete_training_session(uuid,jsonb,text) from public,anon;
revoke execute on function public.call_match(uuid) from public,anon;
revoke execute on function public.get_match_arrival_status(uuid) from public,anon;
revoke execute on function public.set_match_ready(uuid) from public,anon;
revoke execute on function public.forfeit_match(uuid,uuid,text) from public,anon;
revoke execute on function public.complete_tournament(uuid,jsonb) from public,anon;
revoke execute on function public.archive_tournament(uuid) from public,anon;
revoke execute on function public.propagate_match_result() from public,anon,authenticated;
grant execute on function public.start_training_session(uuid),public.pause_training_session(uuid),public.complete_training_session(uuid,jsonb,text),public.call_match(uuid),public.get_match_arrival_status(uuid),public.set_match_ready(uuid),public.forfeit_match(uuid,uuid,text),public.complete_tournament(uuid,jsonb),public.archive_tournament(uuid) to authenticated;

