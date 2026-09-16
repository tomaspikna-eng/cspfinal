-- Strengthen team league lineup integrity.
create or replace function public.validate_league_match_lineup()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_match public.league_matches%rowtype;
  v_expected_team uuid;
  v_members jsonb;
begin
  select * into v_match
  from public.league_matches
  where id = new.match_id;

  if not found then
    raise exception 'League match not found.';
  end if;

  v_expected_team := case when new.side = 'home' then v_match.player1_id else v_match.player2_id end;
  if v_expected_team is null or new.team_id is distinct from v_expected_team then
    raise exception 'Lineup team does not match the selected match side.';
  end if;

  select coalesce(metadata -> 'members', '[]'::jsonb)
    into v_members
  from public.league_players
  where id = new.team_id
    and league_id = v_match.league_id;

  if not found or jsonb_typeof(v_members) <> 'array' then
    raise exception 'Team roster not found.';
  end if;

  if jsonb_array_length(new.slots) > 12 then
    raise exception 'Too many lineup slots.';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(new.slots) as x(value)
    where jsonb_typeof(x.value) <> 'object'
       or not (x.value ? 'slot')
       or not (x.value ? 'name')
       or not (x.value ? 'discipline')
       or coalesce(x.value ->> 'slot', '') !~ '^[1-9][0-9]*$'
       or btrim(coalesce(x.value ->> 'name', '')) = ''
       or btrim(coalesce(x.value ->> 'discipline', '')) = ''
       or not (v_members ? (x.value ->> 'name'))
  ) then
    raise exception 'Invalid lineup slot payload.';
  end if;

  if (
    select count(*) <> count(distinct (x.value ->> 'slot')::integer)
    from jsonb_array_elements(new.slots) as x(value)
  ) then
    raise exception 'Duplicate lineup slot.';
  end if;

  if (
    select count(*) <> count(distinct (x.value ->> 'name'))
    from jsonb_array_elements(new.slots) as x(value)
  ) then
    raise exception 'Duplicate player in lineup.';
  end if;

  if cardinality(new.doubles_slots) not in (0, 2) then
    raise exception 'Doubles selection must contain exactly two slots or be empty.';
  end if;

  if exists (
    select 1
    from unnest(new.doubles_slots) as d(slot_no)
    where not exists (
      select 1
      from jsonb_array_elements(new.slots) as x(value)
      where (x.value ->> 'slot')::smallint = d.slot_no
    )
  ) then
    raise exception 'Doubles selection references an unknown lineup slot.';
  end if;

  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end;
$$;

revoke all on function public.validate_league_match_lineup() from public, anon, authenticated;
