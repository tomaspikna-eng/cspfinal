create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists organizations_owner_id_key
  on public.organizations(owner_id);

alter table public.organizations enable row level security;

drop policy if exists organizations_select_own on public.organizations;
create policy organizations_select_own
on public.organizations
for select
to authenticated
using (owner_id = auth.uid() or public.is_admin(auth.uid()));

drop policy if exists organizations_update_own on public.organizations;
create policy organizations_update_own
on public.organizations
for update
to authenticated
using (owner_id = auth.uid() or public.is_admin(auth.uid()))
with check (owner_id = auth.uid() or public.is_admin(auth.uid()));

create or replace function public.ensure_owned_entity_for_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if new.role = 'club'
     and public.has_feature_access(new.id, 'club_manager')
     and not exists (
       select 1 from public.clubs c where c.owner_id = new.id
     ) then
    insert into public.clubs (owner_id, name)
    values (
      new.id,
      coalesce(nullif(btrim(new.full_name), ''), 'Nový klub')
    )
    on conflict (owner_id) do nothing;
  end if;

  if new.role = 'organization'
     and not exists (
       select 1 from public.organizations o where o.owner_id = new.id
     ) then
    insert into public.organizations (owner_id, name)
    values (
      new.id,
      coalesce(nullif(btrim(new.full_name), ''), 'Nová organizácia')
    )
    on conflict (owner_id) do nothing;
  end if;

  return new;
end;
$function$;

drop trigger if exists profiles_ensure_owned_club on public.profiles;
drop trigger if exists profiles_ensure_owned_entity on public.profiles;

create trigger profiles_ensure_owned_entity
after insert or update of role, plan, full_name, is_admin
on public.profiles
for each row
execute function public.ensure_owned_entity_for_profile();

create or replace function public.sync_owned_entity_name_from_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if new.full_name is distinct from old.full_name then
    if new.role = 'club' then
      update public.clubs
      set name = coalesce(nullif(btrim(new.full_name), ''), name),
          updated_at = now()
      where owner_id = new.id;
    elsif new.role = 'organization' then
      update public.organizations
      set name = coalesce(nullif(btrim(new.full_name), ''), name),
          updated_at = now()
      where owner_id = new.id;
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_sync_club_name_from_profile on public.profiles;
drop trigger if exists trg_sync_owned_entity_name_from_profile on public.profiles;

create trigger trg_sync_owned_entity_name_from_profile
after update of full_name
on public.profiles
for each row
execute function public.sync_owned_entity_name_from_profile();

