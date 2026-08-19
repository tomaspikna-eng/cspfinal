alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check check (notification_type = any (array[
  'new_follower','profile_respect',
  'club_membership_request','club_membership_invite','club_membership_approved','club_membership_rejected','club_membership_cancelled','club_membership_left','club_membership_removed',
  'federation_registration_request','federation_registration_invite','federation_registration_approved','federation_registration_rejected','federation_registration_cancelled','federation_registration_left','federation_registration_removed',
  'followed_player_training','followed_player_match','followed_player_tournament_result','followed_entity_event','followed_entity_tournament'
]::text[]));

create or replace function public.validate_follow_target_role()
returns trigger
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare v_role text;
begin
  select role::text into v_role from public.profiles where id=new.following_profile_id;
  if v_role is null then raise exception 'FOLLOW_TARGET_NOT_FOUND'; end if;
  if v_role not in ('player','club','organization') then
    raise exception 'PROFILE_NOT_FOLLOWABLE';
  end if;
  return new;
end;
$$;

drop trigger if exists profile_follows_validate_target_role on public.profile_follows;
create trigger profile_follows_validate_target_role
before insert or update of following_profile_id on public.profile_follows
for each row execute function public.validate_follow_target_role();

create or replace function public.notify_followers_of_profile(
  p_actor_id uuid,
  p_notification_type text,
  p_entity_type text,
  p_entity_id uuid,
  p_title text,
  p_body text,
  p_action_url text
) returns integer
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare v_count integer;
begin
  insert into public.notifications(recipient_id,actor_id,notification_type,entity_type,entity_id,title,body,action_url)
  select f.follower_id,p_actor_id,p_notification_type,p_entity_type,p_entity_id,p_title,p_body,p_action_url
  from public.profile_follows f
  where f.following_profile_id=p_actor_id
    and f.follower_id<>p_actor_id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.notify_followers_event_published()
returns trigger
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare v_role text; v_name text;
begin
  if new.status='published' and new.visibility='public'
     and (tg_op='INSERT' or old.status is distinct from 'published' or old.visibility is distinct from 'public') then
    select role::text,coalesce(full_name,'Klub') into v_role,v_name from public.profiles where id=new.owner_id;
    if v_role in ('club','organization') then
      perform public.notify_followers_of_profile(
        new.owner_id,'followed_entity_event','event',new.id,
        'Nová udalosť',v_name||' vytvoril udalosť „'||new.title||'“.','/udalost/?id='||new.id::text
      );
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists events_notify_followers_published on public.events;
create trigger events_notify_followers_published
after insert or update of status,visibility on public.events
for each row execute function public.notify_followers_event_published();

create or replace function public.notify_followers_tournament_published()
returns trigger
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare v_role text; v_name text; v_new_public boolean; v_old_public boolean;
begin
  v_new_public := new.visibility='public' and new.status in ('ready','active');
  v_old_public := case when tg_op='UPDATE' then old.visibility='public' and old.status in ('ready','active') else false end;
  if v_new_public and not v_old_public then
    select role::text,coalesce(full_name,'Klub') into v_role,v_name from public.profiles where id=new.owner_id;
    if v_role in ('club','organization') then
      perform public.notify_followers_of_profile(
        new.owner_id,'followed_entity_tournament','tournament',new.id,
        'Nový turnaj',v_name||' vytvoril turnaj „'||new.name||'“.','/turnament/?id='||new.id::text
      );
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists tournaments_notify_followers_published on public.tournaments;
create trigger tournaments_notify_followers_published
after insert or update of status,visibility on public.tournaments
for each row execute function public.notify_followers_tournament_published();

create or replace function public.notify_followers_training_completed()
returns trigger
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare v_role text; v_name text; v_body text;
begin
  if new.status='completed' and (tg_op='INSERT' or old.status is distinct from 'completed') then
    select role::text,coalesce(full_name,'Hráč') into v_role,v_name from public.profiles where id=new.owner_id;
    if v_role='player' then
      v_body := trim(both ' · ' from coalesce(new.sport,'')||case when nullif(new.discipline,'') is not null then ' · '||new.discipline else '' end);
      perform public.notify_followers_of_profile(
        new.owner_id,'followed_player_training','training_session',new.id,
        v_name||' dokončil tréning',nullif(v_body,''),'/profil/?id='||new.owner_id::text||'&view=public'
      );
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists training_sessions_notify_followers_completed on public.training_sessions;
create trigger training_sessions_notify_followers_completed
after insert or update of status on public.training_sessions
for each row execute function public.notify_followers_training_completed();

create or replace function public.notify_followers_match_completed()
returns trigger
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare
  v_tournament_name text;
  v_score text;
  rec record;
begin
  if new.status in ('completed','forfeited') and old.status is distinct from new.status then
    select name into v_tournament_name from public.tournaments where id=new.tournament_id;
    v_score := coalesce(new.score1,0)::text||':'||coalesce(new.score2,0)::text;
    for rec in
      select tp.user_id as actor_id,tp.name as actor_name,opp.name as opp_name
      from (values (new.player1_id,new.player2_id),(new.player2_id,new.player1_id)) x(actor_tp,opp_tp)
      join public.tournament_players tp on tp.id=x.actor_tp
      left join public.tournament_players opp on opp.id=x.opp_tp
      where tp.user_id is not null
    loop
      if exists(select 1 from public.profiles p where p.id=rec.actor_id and p.role::text='player') then
        perform public.notify_followers_of_profile(
          rec.actor_id,'followed_player_match','match',new.id,
          rec.actor_name||' odohral zápas',
          coalesce(v_tournament_name,'Turnaj')||' · '||coalesce(rec.actor_name,'Hráč')||' vs '||coalesce(rec.opp_name,'súper')||' · '||v_score,
          '/turnament/?id='||new.tournament_id::text
        );
      end if;
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists matches_notify_followers_completed on public.matches;
create trigger matches_notify_followers_completed
after update of status on public.matches
for each row execute function public.notify_followers_match_completed();

create or replace function public.notify_followers_tournament_result()
returns trigger
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare v_name text; v_tournament_name text;
begin
  if new.user_id is not null and new.final_position is not null
     and (tg_op='INSERT' or old.final_position is distinct from new.final_position) then
    if exists(select 1 from public.profiles p where p.id=new.user_id and p.role::text='player') then
      select coalesce(tp.name,'Hráč'),coalesce(t.name,'Turnaj') into v_name,v_tournament_name
      from public.tournament_players tp
      join public.tournaments t on t.id=new.tournament_id
      where tp.id=new.tournament_player_id;
      perform public.notify_followers_of_profile(
        new.user_id,'followed_player_tournament_result','tournament',new.tournament_id,
        v_name||' dokončil turnaj',
        v_tournament_name||' · konečné umiestnenie: '||new.final_position::text||'. miesto',
        '/turnament/?id='||new.tournament_id::text
      );
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists tournament_results_notify_followers_position on public.tournament_results;
create trigger tournament_results_notify_followers_position
after insert or update of final_position on public.tournament_results
for each row execute function public.notify_followers_tournament_result();
