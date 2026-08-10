-- CSP membership + federation registration + notification delivery foundation.
-- Live DB was applied first via Supabase execute_sql; this file keeps deploys reproducible.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

alter table public.profiles add column if not exists bio text;
alter table public.organizations add column if not exists organization_type text not null default 'organization';
alter table public.organizations drop constraint if exists organizations_type_check;
alter table public.organizations add constraint organizations_type_check
  check (organization_type in ('organization','federation','association'));

create table if not exists public.club_memberships (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  player_id uuid not null references public.profiles(id) on delete cascade,
  member_role text not null default 'player'
    check (member_role in ('player','captain','coach','referee','manager')),
  request_source text not null check (request_source in ('player_request','club_invite')),
  initiated_by uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending','active','rejected','cancelled','left','removed')),
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists club_memberships_one_open_idx
  on public.club_memberships (club_id, player_id) where status in ('pending','active');
create index if not exists club_memberships_club_status_idx
  on public.club_memberships (club_id, status, created_at desc);
create index if not exists club_memberships_player_status_idx
  on public.club_memberships (player_id, status, created_at desc);
create index if not exists club_memberships_initiated_by_idx
  on public.club_memberships (initiated_by);

create table if not exists public.organization_player_registrations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  player_id uuid not null references public.profiles(id) on delete cascade,
  request_source text not null check (request_source in ('player_request','organization_invite')),
  initiated_by uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending','active','rejected','cancelled','left','removed')),
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists organization_player_registrations_one_open_idx
  on public.organization_player_registrations (organization_id, player_id) where status in ('pending','active');
create index if not exists organization_player_registrations_org_status_idx
  on public.organization_player_registrations (organization_id, status, created_at desc);
create index if not exists organization_player_registrations_player_status_idx
  on public.organization_player_registrations (player_id, status, created_at desc);
create index if not exists organization_player_registrations_initiated_by_idx
  on public.organization_player_registrations (initiated_by);

alter table public.notifications add column if not exists action_url text;
alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check check (
  notification_type in (
    'new_follower','profile_respect',
    'club_membership_request','club_membership_invite','club_membership_approved',
    'club_membership_rejected','club_membership_cancelled','club_membership_left','club_membership_removed',
    'federation_registration_request','federation_registration_invite','federation_registration_approved',
    'federation_registration_rejected','federation_registration_cancelled',
    'federation_registration_left','federation_registration_removed'
  )
);

create table if not exists public.notification_email_outbox (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null unique references public.notifications(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  recipient_email text not null,
  template_key text not null,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending','sending','sent','failed')),
  attempts integer not null default 0 check (attempts >= 0),
  last_error text,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists notification_email_outbox_status_idx
  on public.notification_email_outbox (status, created_at) where status in ('pending','failed');
create index if not exists notification_email_outbox_recipient_idx
  on public.notification_email_outbox (recipient_id, created_at desc);

alter table public.club_memberships enable row level security;
alter table public.organization_player_registrations enable row level security;
alter table public.notification_email_outbox enable row level security;

revoke all on public.club_memberships, public.organization_player_registrations,
  public.notification_email_outbox from public, anon, authenticated;
grant select on public.club_memberships, public.organization_player_registrations to authenticated;
grant insert on public.club_memberships, public.organization_player_registrations to authenticated;
grant update (status) on public.club_memberships, public.organization_player_registrations to authenticated;
grant select (id, club_id, player_id, member_role, status, created_at) on public.club_memberships to anon;
grant select (id, organization_id, player_id, status, created_at) on public.organization_player_registrations to anon;
grant select, insert, update, delete on public.club_memberships,
  public.organization_player_registrations, public.notification_email_outbox to service_role;

revoke select on public.profiles from anon;
grant select (id, full_name, role, avatar_url, cover_url, bio, created_at) on public.profiles to anon;

drop policy if exists "profiles_select_public_safe" on public.profiles;
create policy "profiles_select_public_safe" on public.profiles for select to anon using (true);
drop policy if exists "organizations_select_public" on public.organizations;
create policy "organizations_select_public" on public.organizations for select to anon, authenticated using (true);

drop policy if exists "club_memberships_public_active" on public.club_memberships;
create policy "club_memberships_public_active" on public.club_memberships for select to anon using (status='active');
drop policy if exists "club_memberships_authenticated_read" on public.club_memberships;
create policy "club_memberships_authenticated_read" on public.club_memberships for select to authenticated using (
  status='active' or player_id=(select auth.uid())
  or exists(select 1 from public.clubs c where c.id=club_memberships.club_id and c.owner_id=(select auth.uid()))
  or exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_admin=true)
);
drop policy if exists "club_memberships_create" on public.club_memberships;
create policy "club_memberships_create" on public.club_memberships for insert to authenticated with check (
  status='pending' and initiated_by=(select auth.uid()) and (
    (request_source='player_request' and player_id=(select auth.uid())) or
    (request_source='club_invite' and exists(select 1 from public.clubs c where c.id=club_memberships.club_id and c.owner_id=(select auth.uid())))
  )
);
drop policy if exists "club_memberships_change_status" on public.club_memberships;
create policy "club_memberships_change_status" on public.club_memberships for update to authenticated
using (
  (request_source='club_invite' and player_id=(select auth.uid()) and status in ('pending','active')) or
  (request_source='player_request' and player_id=(select auth.uid()) and status in ('pending','active')) or
  exists(select 1 from public.clubs c where c.id=club_memberships.club_id and c.owner_id=(select auth.uid())) or
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_admin=true)
)
with check (
  (request_source='club_invite' and player_id=(select auth.uid()) and status in ('active','rejected','left')) or
  (request_source='player_request' and player_id=(select auth.uid()) and status in ('cancelled','left')) or
  (exists(select 1 from public.clubs c where c.id=club_memberships.club_id and c.owner_id=(select auth.uid())) and status in ('active','rejected','cancelled','removed')) or
  (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_admin=true) and status in ('active','rejected','cancelled','left','removed'))
);

drop policy if exists "organization_registrations_public_active" on public.organization_player_registrations;
create policy "organization_registrations_public_active" on public.organization_player_registrations for select to anon using (status='active');
drop policy if exists "organization_registrations_authenticated_read" on public.organization_player_registrations;
create policy "organization_registrations_authenticated_read" on public.organization_player_registrations for select to authenticated using (
  status='active' or player_id=(select auth.uid())
  or exists(select 1 from public.organizations o where o.id=organization_player_registrations.organization_id and o.owner_id=(select auth.uid()))
  or exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_admin=true)
);
drop policy if exists "organization_registrations_create" on public.organization_player_registrations;
create policy "organization_registrations_create" on public.organization_player_registrations for insert to authenticated with check (
  status='pending' and initiated_by=(select auth.uid()) and (
    (request_source='player_request' and player_id=(select auth.uid())) or
    (request_source='organization_invite' and exists(select 1 from public.organizations o where o.id=organization_player_registrations.organization_id and o.owner_id=(select auth.uid())))
  )
);
drop policy if exists "organization_registrations_change_status" on public.organization_player_registrations;
create policy "organization_registrations_change_status" on public.organization_player_registrations for update to authenticated
using (
  (request_source='organization_invite' and player_id=(select auth.uid()) and status in ('pending','active')) or
  (request_source='player_request' and player_id=(select auth.uid()) and status in ('pending','active')) or
  exists(select 1 from public.organizations o where o.id=organization_player_registrations.organization_id and o.owner_id=(select auth.uid())) or
  exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_admin=true)
)
with check (
  (request_source='organization_invite' and player_id=(select auth.uid()) and status in ('active','rejected','left')) or
  (request_source='player_request' and player_id=(select auth.uid()) and status in ('cancelled','left')) or
  (exists(select 1 from public.organizations o where o.id=organization_player_registrations.organization_id and o.owner_id=(select auth.uid())) and status in ('active','rejected','cancelled','removed')) or
  (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_admin=true) and status in ('active','rejected','cancelled','left','removed'))
);

drop policy if exists "notification_email_outbox_no_client_read" on public.notification_email_outbox;
create policy "notification_email_outbox_no_client_read" on public.notification_email_outbox
  for select to anon, authenticated using (false);

create or replace function private.membership_status_timestamps()
returns trigger language plpgsql security invoker set search_path='' as $$
begin
  new.updated_at:=now();
  if new.status is distinct from old.status and new.status in ('active','rejected','cancelled','left','removed') then
    new.decided_at:=now();
  end if;
  return new;
end $$;
revoke all on function private.membership_status_timestamps() from public, anon, authenticated;
drop trigger if exists club_memberships_status_timestamps on public.club_memberships;
create trigger club_memberships_status_timestamps before update on public.club_memberships
  for each row execute function private.membership_status_timestamps();
drop trigger if exists organization_registrations_status_timestamps on public.organization_player_registrations;
create trigger organization_registrations_status_timestamps before update on public.organization_player_registrations
  for each row execute function private.membership_status_timestamps();

create or replace function private.emit_membership_notification()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  v_recipient uuid; v_actor uuid:=auth.uid(); v_owner uuid; v_name text;
  v_type text; v_title text; v_body text;
begin
  if tg_table_name='club_memberships' then
    select c.owner_id,c.name into v_owner,v_name from public.clubs c where c.id=new.club_id;
    if tg_op='INSERT' then
      if new.request_source='player_request' then
        v_recipient:=v_owner; v_type:='club_membership_request'; v_title:='Nová žiadosť o členstvo';
        v_body:='Hráč požiadal o členstvo v klube '||coalesce(v_name,'');
      else
        v_recipient:=new.player_id; v_type:='club_membership_invite'; v_title:='Pozvánka do klubu';
        v_body:='Klub '||coalesce(v_name,'')||' vás pozýva medzi členov';
      end if;
    elsif new.status is distinct from old.status then
      v_recipient:=case when new.request_source='player_request' then new.player_id else v_owner end;
      v_type:=case new.status when 'active' then 'club_membership_approved' when 'rejected' then 'club_membership_rejected' when 'cancelled' then 'club_membership_cancelled' when 'left' then 'club_membership_left' when 'removed' then 'club_membership_removed' end;
      v_title:=case new.status when 'active' then 'Členstvo potvrdené' when 'rejected' then 'Členstvo zamietnuté' when 'cancelled' then 'Žiadosť alebo pozvánka zrušená' when 'left' then 'Člen opustil klub' when 'removed' then 'Členstvo ukončené klubom' end;
      v_body:=coalesce(v_name,'Klub');
    end if;
    if v_type is not null and v_recipient is not null then
      insert into public.notifications(recipient_id,actor_id,notification_type,entity_type,entity_id,title,body,action_url)
      values(v_recipient,v_actor,v_type,'club_membership',new.id,v_title,v_body,'/profil/?membership='||new.id::text);
    end if;
  elsif tg_table_name='organization_player_registrations' then
    select o.owner_id,o.name into v_owner,v_name from public.organizations o where o.id=new.organization_id;
    if tg_op='INSERT' then
      if new.request_source='player_request' then
        v_recipient:=v_owner; v_type:='federation_registration_request'; v_title:='Nová žiadosť o registráciu';
        v_body:='Hráč požiadal o registráciu v '||coalesce(v_name,'zväze');
      else
        v_recipient:=new.player_id; v_type:='federation_registration_invite'; v_title:='Pozvánka na registráciu';
        v_body:=coalesce(v_name,'Zväz')||' vás pozýva medzi registrovaných hráčov';
      end if;
    elsif new.status is distinct from old.status then
      v_recipient:=case when new.request_source='player_request' then new.player_id else v_owner end;
      v_type:=case new.status when 'active' then 'federation_registration_approved' when 'rejected' then 'federation_registration_rejected' when 'cancelled' then 'federation_registration_cancelled' when 'left' then 'federation_registration_left' when 'removed' then 'federation_registration_removed' end;
      v_title:=case new.status when 'active' then 'Registrácia potvrdená' when 'rejected' then 'Registrácia zamietnutá' when 'cancelled' then 'Žiadosť alebo pozvánka zrušená' when 'left' then 'Registrácia ukončená hráčom' when 'removed' then 'Registrácia ukončená zväzom' end;
      v_body:=coalesce(v_name,'Zväz');
    end if;
    if v_type is not null and v_recipient is not null then
      insert into public.notifications(recipient_id,actor_id,notification_type,entity_type,entity_id,title,body,action_url)
      values(v_recipient,v_actor,v_type,'federation_registration',new.id,v_title,v_body,'/profil/?registration='||new.id::text);
    end if;
  end if;
  return new;
end $$;
revoke all on function private.emit_membership_notification() from public, anon, authenticated;
drop trigger if exists club_memberships_emit_notification on public.club_memberships;
create trigger club_memberships_emit_notification after insert or update of status on public.club_memberships
  for each row execute function private.emit_membership_notification();
drop trigger if exists organization_registrations_emit_notification on public.organization_player_registrations;
create trigger organization_registrations_emit_notification after insert or update of status on public.organization_player_registrations
  for each row execute function private.emit_membership_notification();

create or replace function private.queue_membership_notification_email()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_email text;
begin
  if new.notification_type not in (
    'club_membership_request','club_membership_invite','club_membership_approved','club_membership_rejected',
    'club_membership_cancelled','club_membership_left','club_membership_removed',
    'federation_registration_request','federation_registration_invite','federation_registration_approved',
    'federation_registration_rejected','federation_registration_cancelled','federation_registration_left','federation_registration_removed'
  ) then return new; end if;
  select p.email into v_email from public.profiles p where p.id=new.recipient_id;
  if v_email is null or btrim(v_email)='' then return new; end if;
  insert into public.notification_email_outbox(notification_id,recipient_id,recipient_email,template_key,payload)
  values(new.id,new.recipient_id,v_email,new.notification_type,
    jsonb_build_object('title',new.title,'body',new.body,'action_url',new.action_url,'entity_type',new.entity_type,'entity_id',new.entity_id))
  on conflict(notification_id) do nothing;
  return new;
end $$;
revoke all on function private.queue_membership_notification_email() from public, anon, authenticated;
drop trigger if exists notifications_queue_membership_email on public.notifications;
create trigger notifications_queue_membership_email after insert on public.notifications
  for each row execute function private.queue_membership_notification_email();

do $$
begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='notifications') then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;
