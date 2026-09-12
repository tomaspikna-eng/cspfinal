create or replace function public.sync_draft_tournament_players(p_tournament_id uuid, p_players jsonb)
returns setof public.tournament_players
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_status text;
  item jsonb;
  n integer:=0;
  v_user_id uuid;
begin
  select status into v_status
  from public.tournaments t
  where t.id=p_tournament_id
    and (t.owner_id=auth.uid() or public.is_admin(auth.uid()))
  for update;

  if v_status is null then
    raise exception 'Tournament not found or access denied';
  end if;

  -- Player list may still be corrected while an ACTIVE tournament has not
  -- created any match rows yet. Once the first match exists the roster is locked.
  if v_status not in ('draft','ready','active')
     or exists(select 1 from public.matches m where m.tournament_id=p_tournament_id) then
    raise exception 'Player list is locked after matches are created';
  end if;

  delete from public.tournament_groups where tournament_id=p_tournament_id;
  delete from public.tournament_players where tournament_id=p_tournament_id;

  for item in select * from jsonb_array_elements(coalesce(p_players,'[]'::jsonb))
  loop
    n:=n+1;
    v_user_id:=nullif(item->>'user_id','')::uuid;
    insert into public.tournament_players(tournament_id,name,user_id,seed)
    values(
      p_tournament_id,
      nullif(trim(item->>'name'),''),
      v_user_id,
      coalesce((item->>'seed')::integer,n)
    );
  end loop;

  return query
    select * from public.tournament_players
    where tournament_id=p_tournament_id
    order by seed;
end;
$function$;

