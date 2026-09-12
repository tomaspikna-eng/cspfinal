create unique index if not exists clubs_owner_id_unique
on public.clubs(owner_id);

create or replace function public.enforce_club_manager_access()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if auth.uid() is not null and auth.uid() <> new.owner_id then
    raise exception 'A club can only be created for the authenticated owner.';
  end if;

  if not public.has_feature_access(new.owner_id, 'club_manager') then
    raise exception 'Club Manager access required to create a club.';
  end if;

  return new;
end;
$function$;

create or replace function public.ensure_owned_club_for_profile()
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

  return new;
end;
$function$;

drop trigger if exists profiles_ensure_owned_club on public.profiles;
create trigger profiles_ensure_owned_club
after insert or update of role, plan, full_name
on public.profiles
for each row
execute function public.ensure_owned_club_for_profile();

insert into public.clubs (owner_id, name)
values (
  '71bd8491-f43f-4f3c-a82a-32d121966ee7'::uuid,
  'Trenčiansky Point'
)
on conflict (owner_id) do update
set name = excluded.name,
    updated_at = now();

