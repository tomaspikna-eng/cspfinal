-- Connect Sports Pro — PRO+ plan
-- Internal slug: pro_plus; public label: PRO+
-- Tier order: free < pro < pro_plus < ultra < elite

alter type public.profile_plan
  add value if not exists 'pro_plus' before 'ultra';

comment on type public.profile_plan is
  'CSP subscription plans ordered as free, pro, pro_plus, ultra and elite. The public label for pro_plus is PRO+.';

comment on column public.profiles.plan is
  'Subscription tier: free/pro/pro_plus/ultra/elite. Admin remains an independent override through is_admin.';

alter table public.feature_gates
  drop constraint if exists feature_gates_min_plan_check;

alter table public.feature_gates
  add constraint feature_gates_min_plan_check
  check (min_plan in ('free','pro','pro_plus','ultra','elite'));

update public.feature_gates
set min_plan = 'pro_plus',
    description = 'Create and organize tournaments. Available from PRO+; unlimited for organizer tiers.'
where feature_key = 'tournament_create';

update public.feature_gates
set min_plan = 'pro_plus',
    description = 'Use the tournament bracket and table generator. Available from PRO+.'
where feature_key = 'table_generator';

insert into public.feature_gates (feature_key,min_plan,description)
values
  ('event_create','pro_plus','Create standalone events and multi-round seasons. Available from PRO+.'),
  ('league_create','pro_plus','Create and manage leagues. Available from PRO+.')
on conflict (feature_key) do update
set min_plan = excluded.min_plan,
    description = excluded.description;

create or replace function public.has_plan_at_least(uid uuid, required text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case public.current_plan(uid)
    when 'elite' then required in ('free','pro','pro_plus','ultra','elite')
    when 'ultra' then required in ('free','pro','pro_plus','ultra')
    when 'pro_plus' then required in ('free','pro','pro_plus')
    when 'pro' then required in ('free','pro')
    else required = 'free'
  end;
$$;

comment on function public.has_plan_at_least(uuid,text) is
  'Tier ordering free < pro < pro_plus < ultra < elite. Admin maps to elite through current_plan().';

create or replace function public.remaining_tournament_quota(uid uuid)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  effective_plan text;
begin
  if public.is_admin(uid) then
    return null;
  end if;

  effective_plan := public.current_plan(uid);

  if effective_plan in ('pro_plus','ultra','elite') then
    return null;
  end if;

  return 0;
end;
$$;

comment on function public.remaining_tournament_quota(uuid) is
  'NULL means unlimited tournament creation for PRO+, Ultra, Elite and admins. Free and Pro return 0.';

create or replace function public.can_create_tournament(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.has_feature_access(uid,'tournament_create')
     and (
       public.remaining_tournament_quota(uid) is null
       or public.remaining_tournament_quota(uid) > 0
     );
$$;

comment on function public.can_create_tournament(uuid) is
  'True for PRO+, Ultra, Elite and admins. Free and Pro cannot create new tournaments.';

revoke execute on function public.has_plan_at_least(uuid,text) from public,anon;
revoke execute on function public.remaining_tournament_quota(uuid) from public,anon;
revoke execute on function public.can_create_tournament(uuid) from public,anon;
grant execute on function public.has_plan_at_least(uuid,text) to authenticated,service_role;
grant execute on function public.remaining_tournament_quota(uuid) to authenticated,service_role;
grant execute on function public.can_create_tournament(uuid) to authenticated,service_role;

-- New competitions require PRO+, but their owners retain access to records
-- they created previously if their subscription later changes.

drop policy if exists tournaments_owner_all on public.tournaments;
drop policy if exists tournaments_owner_select on public.tournaments;
drop policy if exists tournaments_owner_insert on public.tournaments;
drop policy if exists tournaments_owner_update on public.tournaments;
drop policy if exists tournaments_owner_delete on public.tournaments;

create policy tournaments_owner_select
on public.tournaments for select
to authenticated
using (owner_id = (select auth.uid()));

create policy tournaments_owner_insert
on public.tournaments for insert
to authenticated
with check (
  owner_id = (select auth.uid())
  and (select public.can_create_tournament((select auth.uid())))
);

create policy tournaments_owner_update
on public.tournaments for update
to authenticated
using (owner_id = (select auth.uid()))
with check (owner_id = (select auth.uid()));

create policy tournaments_owner_delete
on public.tournaments for delete
to authenticated
using (owner_id = (select auth.uid()));

drop policy if exists events_owner_all on public.events;
drop policy if exists events_owner_select on public.events;
drop policy if exists events_owner_insert on public.events;
drop policy if exists events_owner_update on public.events;
drop policy if exists events_owner_delete on public.events;

create policy events_owner_select
on public.events for select
to authenticated
using (owner_id = (select auth.uid()));

create policy events_owner_insert
on public.events for insert
to authenticated
with check (
  owner_id = (select auth.uid())
  and (select public.has_feature_access((select auth.uid()),'event_create'))
  and (
    club_id is null
    or exists (
      select 1 from public.clubs c
      where c.id = events.club_id
        and c.owner_id = (select auth.uid())
    )
  )
);

create policy events_owner_update
on public.events for update
to authenticated
using (owner_id = (select auth.uid()))
with check (
  owner_id = (select auth.uid())
  and (
    club_id is null
    or exists (
      select 1 from public.clubs c
      where c.id = events.club_id
        and c.owner_id = (select auth.uid())
    )
  )
);

create policy events_owner_delete
on public.events for delete
to authenticated
using (owner_id = (select auth.uid()));

drop policy if exists event_series_owner_insert on public.event_series;

create policy event_series_owner_insert
on public.event_series for insert
to authenticated
with check (
  owner_id = (select auth.uid())
  and (select public.has_feature_access((select auth.uid()),'event_create'))
  and (
    club_id is null
    or exists (
      select 1 from public.clubs c
      where c.id = event_series.club_id
        and c.owner_id = (select auth.uid())
    )
  )
);

drop policy if exists leagues_owner_insert on public.leagues;

create policy leagues_owner_insert
on public.leagues for insert
to authenticated
with check (
  owner_id = (select auth.uid())
  and (select public.has_feature_access((select auth.uid()),'league_create'))
);

