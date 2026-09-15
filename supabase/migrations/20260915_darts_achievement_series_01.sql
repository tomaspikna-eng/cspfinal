insert into public.achievement_series(code,name,description,sort_order,active)
values('darts_01','Darts Series 01','Šípkarské výkonové achievementy merané zo scoreboardu.',20,true)
on conflict(code) do update set name=excluded.name,description=excluded.description,sort_order=excluded.sort_order,active=true;

create table if not exists public.darts_visit_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  training_session_id uuid references public.training_sessions(id) on delete set null,
  discipline text not null,
  score integer not null check (score between 0 and 180),
  remaining_before integer not null,
  remaining_after integer not null,
  is_bust boolean not null default false,
  is_checkout boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.darts_visit_events enable row level security;
drop policy if exists darts_visit_events_select_own on public.darts_visit_events;
create policy darts_visit_events_select_own on public.darts_visit_events for select to authenticated using (user_id = auth.uid());

insert into public.achievement_definitions
(code,series_code,name,description,category,metric,target_value,points,rarity,sort_order,active,auto_award,created_at,updated_at)
values
('darts_180_1','darts_01','Prvá 180','Hoď prvú 180.','sipky','darts_180_count',1,10,'bronze',101,true,false,now(),now()),
('darts_180_10','darts_01','Desiatka 180','Hoď 10× 180.','sipky','darts_180_count',10,20,'silver',102,true,false,now(),now()),
('darts_180_50','darts_01','Päťdesiat 180','Hoď 50× 180.','sipky','darts_180_count',50,35,'gold',103,true,false,now(),now()),
('darts_180_100','darts_01','Stovka 180','Hoď 100× 180.','sipky','darts_180_count',100,50,'platinum',104,true,false,now(),now()),
('darts_checkout_100','darts_01','High checkout 100+','Zavri leg checkoutom nad 100.','sipky','darts_checkout_max',101,15,'silver',105,true,false,now(),now()),
('darts_checkout_120','darts_01','High checkout 120+','Zavri leg checkoutom 120 alebo viac.','sipky','darts_checkout_max',120,25,'gold',106,true,false,now(),now()),
('darts_checkout_150','darts_01','High checkout 150+','Zavri leg checkoutom 150 alebo viac.','sipky','darts_checkout_max',150,40,'platinum',107,true,false,now(),now()),
('darts_streak_100x3','darts_01','Pressure 100+','Zahraj 3 návštevy 100+ za sebou.','sipky','darts_streak_100',3,15,'silver',108,true,false,now(),now()),
('darts_streak_140x3','darts_01','Pressure 140+','Zahraj 3 návštevy 140+ za sebou.','sipky','darts_streak_140',3,25,'gold',109,true,false,now(),now())
on conflict(code) do update set
series_code=excluded.series_code,name=excluded.name,description=excluded.description,category=excluded.category,metric=excluded.metric,
target_value=excluded.target_value,points=excluded.points,rarity=excluded.rarity,sort_order=excluded.sort_order,active=true,auto_award=false,updated_at=now();

create or replace function public.refresh_darts_achievements(p_user_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
declare v_180 integer:=0; v_checkout integer:=0; v_streak100 integer:=0; v_streak140 integer:=0;
begin
  if p_user_id is null then return; end if;
  select count(*) filter(where not is_bust and score=180)::int,
         coalesce(max(case when is_checkout and not is_bust then remaining_before else 0 end),0)::int
    into v_180,v_checkout
  from public.darts_visit_events where user_id=p_user_id;

  select coalesce(max(cnt),0)::int into v_streak100 from (
    select count(*) cnt from (
      select training_session_id,created_at,id,(not is_bust and score>=100) ok,
             sum(case when (not is_bust and score>=100) then 0 else 1 end) over(partition by training_session_id order by created_at,id) grp
      from public.darts_visit_events where user_id=p_user_id and training_session_id is not null
    ) q where ok group by training_session_id,grp
  ) z;

  select coalesce(max(cnt),0)::int into v_streak140 from (
    select count(*) cnt from (
      select training_session_id,created_at,id,(not is_bust and score>=140) ok,
             sum(case when (not is_bust and score>=140) then 0 else 1 end) over(partition by training_session_id order by created_at,id) grp
      from public.darts_visit_events where user_id=p_user_id and training_session_id is not null
    ) q where ok group by training_session_id,grp
  ) z;

  insert into public.player_achievement_progress(user_id,achievement_code,current_value,target_value,unlocked,updated_at)
  select p_user_id,d.code,
    case d.metric when 'darts_180_count' then v_180 when 'darts_checkout_max' then v_checkout when 'darts_streak_100' then v_streak100 when 'darts_streak_140' then v_streak140 else 0 end,
    d.target_value,
    (case d.metric when 'darts_180_count' then v_180 when 'darts_checkout_max' then v_checkout when 'darts_streak_100' then v_streak100 when 'darts_streak_140' then v_streak140 else 0 end)>=d.target_value,
    now()
  from public.achievement_definitions d where d.active and d.series_code='darts_01'
  on conflict(user_id,achievement_code) do update set current_value=excluded.current_value,target_value=excluded.target_value,unlocked=public.player_achievement_progress.unlocked or excluded.unlocked,updated_at=now();

  insert into public.player_achievements(user_id,achievement_code,unlocked_at,source)
  select p.user_id,p.achievement_code,now(),'darts_achievement_engine'
  from public.player_achievement_progress p join public.achievement_definitions d on d.code=p.achievement_code and d.active
  where p.user_id=p_user_id and p.unlocked and d.series_code='darts_01'
  on conflict(user_id,achievement_code) do nothing;
end;$$;

create or replace function public.record_darts_visit(p_training_session_id uuid,p_discipline text,p_score integer,p_remaining_before integer,p_remaining_after integer,p_is_bust boolean default false)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_id uuid; v_checkout boolean;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_score is null or p_score<0 or p_score>180 then raise exception 'invalid darts score'; end if;
  if p_remaining_before is null or p_remaining_after is null then raise exception 'remaining score required'; end if;
  if p_training_session_id is not null and not exists(select 1 from public.training_sessions ts where ts.id=p_training_session_id and ts.owner_id=v_uid and ts.sport='darts') then raise exception 'invalid training session'; end if;
  v_checkout := (not coalesce(p_is_bust,false) and p_remaining_after=0 and p_remaining_before=p_score);
  insert into public.darts_visit_events(user_id,training_session_id,discipline,score,remaining_before,remaining_after,is_bust,is_checkout)
  values(v_uid,p_training_session_id,coalesce(nullif(trim(p_discipline),''),'501'),p_score,p_remaining_before,p_remaining_after,coalesce(p_is_bust,false),v_checkout)
  returning id into v_id;
  perform public.refresh_darts_achievements(v_uid);
  return v_id;
end;$$;

grant execute on function public.record_darts_visit(uuid,text,integer,integer,integer,boolean) to authenticated;
revoke all on function public.refresh_darts_achievements(uuid) from public,anon,authenticated;
