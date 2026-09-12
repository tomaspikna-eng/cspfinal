create or replace function public.sync_owned_club_name_from_profile()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.role = 'club' and new.full_name is distinct from old.full_name then
    update public.clubs
    set name = new.full_name,
        updated_at = now()
    where owner_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_sync_club_name_from_profile on public.profiles;
create trigger trg_sync_club_name_from_profile
after update of full_name on public.profiles
for each row
execute function public.sync_owned_club_name_from_profile();

