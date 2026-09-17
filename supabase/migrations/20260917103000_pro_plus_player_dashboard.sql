-- Connect Sports Pro — authenticated PRO+ player dashboard
-- Consolidates the existing player profile and achievement engines behind a
-- plan-gated RPC and adds a small owner-only equipment profile.

create table if not exists public.player_gear (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  board_name text,
  equipment_name text,
  motto text,
  updated_at timestamptz not null default now(),
  constraint player_gear_board_name_length check (char_length(coalesce(board_name, '')) <= 120),
  constraint player_gear_equipment_name_length check (char_length(coalesce(equipment_name, '')) <= 120),
  constraint player_gear_motto_length check (char_length(coalesce(motto, '')) <= 240)
);

comment on table public.player_gear is
  'Optional equipment details displayed on the authenticated PRO+ player dashboard.';

alter table public.player_gear enable row level security;

revoke all on table public.player_gear from public, anon;
grant select, insert, update on table public.player_gear to authenticated, service_role;

drop policy if exists player_gear_owner_select on public.player_gear;
create policy player_gear_owner_select
on public.player_gear
for select
to authenticated
using (
  (select auth.uid()) = user_id
  and public.has_plan_at_least((select auth.uid()), 'pro_plus')
);

drop policy if exists player_gear_owner_insert on public.player_gear;
create policy player_gear_owner_insert
on public.player_gear
for insert
to authenticated
with check (
  (select auth.uid()) = user_id
  and public.has_plan_at_least((select auth.uid()), 'pro_plus')
);

drop policy if exists player_gear_owner_update on public.player_gear;
create policy player_gear_owner_update
on public.player_gear
for update
to authenticated
using (
  (select auth.uid()) = user_id
  and public.has_plan_at_least((select auth.uid()), 'pro_plus')
)
with check (
  (select auth.uid()) = user_id
  and public.has_plan_at_least((select auth.uid()), 'pro_plus')
);

create or replace function public.get_my_pro_plus_dashboard()
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_profile jsonb;
  v_achievements jsonb;
  v_ihs jsonb;
  v_gear jsonb;
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  if not public.has_plan_at_least(v_user_id, 'pro_plus') then
    raise exception 'PRO+ plan required' using errcode = '42501';
  end if;

  v_profile := public.get_my_player_profile_dashboard();
  v_achievements := public.get_my_achievements();
  v_ihs := public.get_my_ihs_overview();

  select jsonb_build_object(
    'board_name', g.board_name,
    'equipment_name', g.equipment_name,
    'motto', g.motto,
    'updated_at', g.updated_at
  )
  into v_gear
  from public.player_gear g
  where g.user_id = v_user_id;

  return coalesce(v_profile, '{}'::jsonb) || jsonb_build_object(
    'achievements', coalesce(v_achievements, '{}'::jsonb),
    'ihs', coalesce(v_ihs, '{}'::jsonb),
    'gear', coalesce(v_gear, jsonb_build_object(
      'board_name', null,
      'equipment_name', null,
      'motto', null,
      'updated_at', null
    ))
  );
end;
$$;

comment on function public.get_my_pro_plus_dashboard() is
  'Returns the authenticated player dashboard only for PRO+, Ultra, Elite or admin accounts.';

revoke all on function public.get_my_pro_plus_dashboard() from public, anon;
grant execute on function public.get_my_pro_plus_dashboard() to authenticated, service_role;

create or replace function public.update_my_pro_plus_gear(
  p_board_name text,
  p_equipment_name text,
  p_motto text
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_row public.player_gear;
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  if not public.has_plan_at_least(v_user_id, 'pro_plus') then
    raise exception 'PRO+ plan required' using errcode = '42501';
  end if;

  if char_length(coalesce(p_board_name, '')) > 120
     or char_length(coalesce(p_equipment_name, '')) > 120
     or char_length(coalesce(p_motto, '')) > 240 then
    raise exception 'gear value is too long' using errcode = '22001';
  end if;

  insert into public.player_gear(user_id, board_name, equipment_name, motto, updated_at)
  values (
    v_user_id,
    nullif(btrim(p_board_name), ''),
    nullif(btrim(p_equipment_name), ''),
    nullif(btrim(p_motto), ''),
    now()
  )
  on conflict (user_id) do update set
    board_name = excluded.board_name,
    equipment_name = excluded.equipment_name,
    motto = excluded.motto,
    updated_at = now()
  returning * into v_row;

  return jsonb_build_object(
    'board_name', v_row.board_name,
    'equipment_name', v_row.equipment_name,
    'motto', v_row.motto,
    'updated_at', v_row.updated_at
  );
end;
$$;

comment on function public.update_my_pro_plus_gear(text, text, text) is
  'Creates or updates equipment details for the authenticated PRO+ player.';

revoke all on function public.update_my_pro_plus_gear(text, text, text) from public, anon;
grant execute on function public.update_my_pro_plus_gear(text, text, text) to authenticated, service_role;
