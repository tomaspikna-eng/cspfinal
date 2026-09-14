create or replace function public.sync_started_match_resource()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status in ('in_progress','live') and coalesce(old.status,'') not in ('in_progress','live') then
    update public.tournament_resources
    set status='in_progress', tablet_last_seen_at=now(), updated_at=now()
    where current_match_id=new.id and tournament_id=new.tournament_id and is_active=true;

    update public.tournament_resource_assignments
    set started_at=coalesce(started_at,now())
    where match_id=new.id and released_at is null;
  end if;
  return new;
end;
$$;
