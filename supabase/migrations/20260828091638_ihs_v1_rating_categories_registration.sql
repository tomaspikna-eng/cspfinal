-- CSP IHS v1: player rating/level foundation, tournament registration categories,
-- verified tournament result processing, and welcome notification/email queue.

create or replace function public.normalize_ihs_sport(p_sport text)
returns text
language plpgsql
immutable
as $$
declare
  v text := lower(regexp_replace(btrim(coalesce(p_sport,'')), '\s+', ' ', 'g'));
begin
  return case
    when v in ('biliard','billiard','billiards','pool','snooker','heyball','hey ball') then 'billiards'
    when v in ('šípky','sipky','darts') then 'darts'
    when v in ('bowling') then 'bowling'
    when v in ('tenis','tennis') then 'tennis'
    when v in ('stolný tenis','stolny tenis','table tennis','ping pong','ping-pong') then 'table_tennis'
    when v in ('padel') then 'padel'
    when v in ('šach','sach','chess') then 'chess'
    when v in ('bedminton','badminton') then 'badminton'
    when v in ('karty','cards') then 'cards'
    else nullif(v,'')
  end;
end;
$$;

create or replace function public.ihs_level_for_rating(p_rating numeric)
returns text
language sql
immutable
as $$
  select case
    when coalesce(p_rating, 2.50) >= 10.00 then 'world_class'
    when coalesce(p_rating, 2.50) >= 7.00 then 'elite'
    when coalesce(p_rating, 2.50) >= 4.00 then 'competitive'
    else 'amateur'
  end;
$$;

create table if not exists public.player_ihs_profiles (
  player_id uuid primary key references public.profiles(id) on delete cascade,
  default_rating numeric(4,2) not null default 2.50 check (default_rating between 1.00 and 10.00),
  explanation_queued_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.player_ihs_ratings (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.profiles(id) on delete cascade,
  sport_key text not null,
  sport text not null,
  rating numeric(4,2) not null default 2.50 check (rating between 1.00 and 10.00),
  level text generated always as (
    case
      when rating >= 10.00 then 'world_class'
      when rating >= 7.00 then 'elite'
      when rating >= 4.00 then 'competitive'
      else 'amateur'
    end
  ) stored,
  handicap jsonb not null default '{}'::jsonb,
  verified_matches integer not null default 0 check (verified_matches >= 0),
  wins integer not null default 0 check (wins >= 0),
  losses integer not null default 0 check (losses >= 0),
  last_match_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(player_id, sport_key)
);

create index if not exists player_ihs_ratings_sport_level_idx
  on public.player_ihs_ratings(sport_key, level, rating desc);

create table if not exists public.ihs_rating_events (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null unique references public.matches(id) on delete cascade,
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  sport_key text not null,
  player1_id uuid not null references public.profiles(id) on delete cascade,
  player2_id uuid not null references public.profiles(id) on delete cascade,
  winner_id uuid not null references public.profiles(id) on delete cascade,
  player1_rating_before numeric(4,2) not null,
  player1_rating_after numeric(4,2) not null,
  player2_rating_before numeric(4,2) not null,
  player2_rating_after numeric(4,2) not null,
  k_factor numeric(4,2) not null,
  created_at timestamptz not null default now()
);

create index if not exists ihs_rating_events_player1_idx on public.ihs_rating_events(player1_id, created_at desc);
create index if not exists ihs_rating_events_player2_idx on public.ihs_rating_events(player2_id, created_at desc);

alter table public.player_ihs_profiles enable row level security;
alter table public.player_ihs_ratings enable row level security;
alter table public.ihs_rating_events enable row level security;

drop policy if exists player_ihs_profiles_read on public.player_ihs_profiles;
create policy player_ihs_profiles_read on public.player_ihs_profiles
for select using (true);

drop policy if exists player_ihs_ratings_read on public.player_ihs_ratings;
create policy player_ihs_ratings_read on public.player_ihs_ratings
for select using (true);

drop policy if exists ihs_rating_events_own_read on public.ihs_rating_events;
create policy ihs_rating_events_own_read on public.ihs_rating_events
for select using (
  player1_id = auth.uid() or player2_id = auth.uid() or public.is_admin(auth.uid())
);

grant select on public.player_ihs_profiles, public.player_ihs_ratings to anon, authenticated;
grant select on public.ihs_rating_events to authenticated;

create or replace function public.ensure_player_ihs_profile(p_player_id uuid)
returns public.player_ihs_profiles
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.player_ihs_profiles;
begin
  insert into public.player_ihs_profiles(player_id)
  values(p_player_id)
  on conflict(player_id) do nothing;

  select * into v_row
  from public.player_ihs_profiles
  where player_id = p_player_id;

  return v_row;
end;
$$;

create or replace function public.ensure_player_ihs_rating(p_player_id uuid, p_sport text)
returns public.player_ihs_ratings
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_profile public.player_ihs_profiles;
  v_row public.player_ihs_ratings;
  v_key text;
  v_sport text;
begin
  v_key := public.normalize_ihs_sport(p_sport);
  if v_key is null then
    raise exception 'CSP IHS: sport is required';
  end if;

  v_sport := nullif(btrim(p_sport),'');
  v_profile := public.ensure_player_ihs_profile(p_player_id);

  insert into public.player_ihs_ratings(player_id, sport_key, sport, rating)
  values(p_player_id, v_key, coalesce(v_sport, v_key), v_profile.default_rating)
  on conflict(player_id, sport_key) do update
    set sport = excluded.sport,
        updated_at = now()
  returning * into v_row;

  return v_row;
end;
$$;

-- Existing notification type check + IHS welcome.
alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check check (
  notification_type = any(array[
    'new_follower'::text,
    'profile_respect'::text,
    'club_membership_request'::text,
    'club_membership_invite'::text,
    'club_membership_approved'::text,
    'club_membership_rejected'::text,
    'club_membership_cancelled'::text,
    'club_membership_left'::text,
    'club_membership_removed'::text,
    'federation_registration_request'::text,
    'federation_registration_invite'::text,
    'federation_registration_approved'::text,
    'federation_registration_rejected'::text,
    'federation_registration_cancelled'::text,
    'federation_registration_left'::text,
    'federation_registration_removed'::text,
    'followed_player_training'::text,
    'followed_player_match'::text,
    'followed_player_tournament_result'::text,
    'followed_entity_event'::text,
    'followed_entity_tournament'::text,
    'ihs_welcome'::text
  ])
);

create or replace function public.init_ihs_for_profile()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_created uuid;
  v_notification_id uuid;
begin
  if new.role::text <> 'player' then
    return new;
  end if;

  insert into public.player_ihs_profiles(player_id)
  values(new.id)
  on conflict(player_id) do nothing
  returning player_id into v_created;

  if v_created is not null and new.email is not null then
    insert into public.notifications(
      recipient_id, actor_id, notification_type, entity_type, entity_id,
      title, body, action_url
    ) values (
      new.id, null, 'ihs_welcome', 'ihs_profile', new.id,
      'CSP IHS je aktívny',
      'Od registrácie sa ti automaticky počíta CSP Rating a Level z VERIFIED turnajových výsledkov.',
      '/profil/'
    ) returning id into v_notification_id;

    insert into public.notification_email_outbox(
      notification_id, recipient_id, recipient_email, template_key, payload
    ) values (
      v_notification_id,
      new.id,
      new.email,
      'ihs_welcome',
      jsonb_build_object(
        'title','CSP International Handicap System',
        'body','CSP IHS je aktívny od tvojej registrácie. Rating a Level sa menia automaticky podľa VERIFIED turnajových výsledkov. Hodnoty nie je možné ručne upravovať.',
        'action_url','/profil/',
        'entity_type','ihs_profile',
        'entity_id',new.id
      )
    );

    update public.player_ihs_profiles
      set explanation_queued_at = now(), updated_at = now()
      where player_id = new.id;
  end if;

  return new;
end;
$$;

drop trigger if exists profiles_ihs_init on public.profiles;
create trigger profiles_ihs_init
after insert or update of role on public.profiles
for each row execute function public.init_ihs_for_profile();

create or replace function public.init_ihs_for_player_discipline()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.ensure_player_ihs_rating(new.player_id, new.sport);
  return new;
end;
$$;

drop trigger if exists player_disciplines_ihs_init on public.player_disciplines;
create trigger player_disciplines_ihs_init
after insert or update of player_id, sport on public.player_disciplines
for each row execute function public.init_ihs_for_player_discipline();

alter table public.tournaments
  add column if not exists ihs_allowed_categories text[] not null
  default array['amateur','competitive','elite','world_class']::text[];

alter table public.tournaments drop constraint if exists tournaments_ihs_allowed_categories_check;
alter table public.tournaments add constraint tournaments_ihs_allowed_categories_check check (
  cardinality(ihs_allowed_categories) > 0
  and ihs_allowed_categories <@ array['amateur','competitive','elite','world_class']::text[]
);

create or replace function public.resolve_tournament_player_profile_id(
  p_user_id uuid,
  p_player_identity_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_profile_id uuid;
begin
  if p_user_id is not null then
    return p_user_id;
  end if;

  if p_player_identity_id is not null then
    select claimed_profile_id into v_profile_id
    from public.player_identities
    where id = p_player_identity_id
      and status = 'claimed';
  end if;

  return v_profile_id;
end;
$$;

create or replace function public.validate_tournament_player_ihs()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_profile_id uuid;
  v_sport text;
  v_allowed text[];
  v_rating public.player_ihs_ratings;
begin
  v_profile_id := public.resolve_tournament_player_profile_id(new.user_id, new.player_identity_id);

  -- Organizer-entered external players without a CSP identity remain possible.
  if v_profile_id is null then
    return new;
  end if;

  select sport, ihs_allowed_categories
    into v_sport, v_allowed
  from public.tournaments
  where id = new.tournament_id;

  if v_sport is null then
    return new;
  end if;

  v_rating := public.ensure_player_ihs_rating(v_profile_id, v_sport);

  if not (v_rating.level = any(v_allowed)) then
    raise exception using
      errcode = '23514',
      message = format('CSP IHS: hráč patrí do kategórie %s, ktorá nie je povolená pre tento turnaj.', v_rating.level);
  end if;

  return new;
end;
$$;

drop trigger if exists trg_validate_tournament_player_ihs on public.tournament_players;
create trigger trg_validate_tournament_player_ihs
before insert or update of tournament_id, user_id, player_identity_id on public.tournament_players
for each row execute function public.validate_tournament_player_ihs();

create or replace function public.process_verified_match_ihs()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_sport text;
  v_sport_key text;
  v_p1 uuid;
  v_p2 uuid;
  v_winner uuid;
  v_r1 public.player_ihs_ratings;
  v_r2 public.player_ihs_ratings;
  v_before1 numeric(4,2);
  v_before2 numeric(4,2);
  v_after1 numeric(4,2);
  v_after2 numeric(4,2);
  v_expected1 numeric;
  v_score1 numeric;
  v_delta numeric;
  v_k numeric(4,2);
begin
  if new.status <> 'completed' or new.winner_id is null or new.player1_id is null or new.player2_id is null then
    return new;
  end if;

  if exists(select 1 from public.ihs_rating_events where match_id = new.id) then
    return new;
  end if;

  select t.sport into v_sport
  from public.tournaments t
  where t.id = new.tournament_id;

  v_sport_key := public.normalize_ihs_sport(v_sport);
  if v_sport_key is null then
    return new;
  end if;

  select coalesce(tp.user_id, pi.claimed_profile_id)
    into v_p1
  from public.tournament_players tp
  left join public.player_identities pi on pi.id = tp.player_identity_id and pi.status = 'claimed'
  where tp.id = new.player1_id;

  select coalesce(tp.user_id, pi.claimed_profile_id)
    into v_p2
  from public.tournament_players tp
  left join public.player_identities pi on pi.id = tp.player_identity_id and pi.status = 'claimed'
  where tp.id = new.player2_id;

  if v_p1 is null or v_p2 is null or v_p1 = v_p2 then
    return new;
  end if;

  if new.winner_id = new.player1_id then
    v_winner := v_p1;
    v_score1 := 1;
  elsif new.winner_id = new.player2_id then
    v_winner := v_p2;
    v_score1 := 0;
  else
    return new;
  end if;

  v_r1 := public.ensure_player_ihs_rating(v_p1, v_sport);
  v_r2 := public.ensure_player_ihs_rating(v_p2, v_sport);
  v_before1 := v_r1.rating;
  v_before2 := v_r2.rating;

  -- Elo-style update directly on the public 1.00-10.00 IHS scale.
  -- Faster calibration for the first 10 VERIFIED matches, then stabilised.
  v_k := case when least(v_r1.verified_matches, v_r2.verified_matches) < 10 then 0.60 else 0.35 end;
  v_expected1 := 1.0 / (1.0 + power(10.0, (v_before2 - v_before1) / 2.0));
  v_delta := v_k * (v_score1 - v_expected1);

  v_after1 := round(greatest(1.00, least(10.00, v_before1 + v_delta))::numeric, 2);
  v_after2 := round(greatest(1.00, least(10.00, v_before2 - v_delta))::numeric, 2);

  update public.player_ihs_ratings
  set rating = v_after1,
      verified_matches = verified_matches + 1,
      wins = wins + case when v_winner = v_p1 then 1 else 0 end,
      losses = losses + case when v_winner = v_p2 then 1 else 0 end,
      last_match_at = coalesce(new.completed_at, now()),
      updated_at = now()
  where player_id = v_p1 and sport_key = v_sport_key;

  update public.player_ihs_ratings
  set rating = v_after2,
      verified_matches = verified_matches + 1,
      wins = wins + case when v_winner = v_p2 then 1 else 0 end,
      losses = losses + case when v_winner = v_p1 then 1 else 0 end,
      last_match_at = coalesce(new.completed_at, now()),
      updated_at = now()
  where player_id = v_p2 and sport_key = v_sport_key;

  insert into public.ihs_rating_events(
    match_id, tournament_id, sport_key, player1_id, player2_id, winner_id,
    player1_rating_before, player1_rating_after,
    player2_rating_before, player2_rating_after, k_factor
  ) values (
    new.id, new.tournament_id, v_sport_key, v_p1, v_p2, v_winner,
    v_before1, v_after1, v_before2, v_after2, v_k
  );

  return new;
end;
$$;

drop trigger if exists matches_ihs_verified_result_insert on public.matches;
create trigger matches_ihs_verified_result_insert
after insert on public.matches
for each row execute function public.process_verified_match_ihs();

drop trigger if exists matches_ihs_verified_result_update on public.matches;
create trigger matches_ihs_verified_result_update
after update of status, winner_id, player1_id, player2_id on public.matches
for each row execute function public.process_verified_match_ihs();

create or replace function public.get_my_ihs_overview()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_plan text;
  v_default numeric(4,2) := 2.50;
  v_primary_sport text;
  v_current public.player_ihs_ratings;
  v_ratings jsonb;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select plan::text into v_plan from public.profiles where id = v_uid;
  if not found then
    raise exception 'Profile not found';
  end if;

  select default_rating into v_default
  from public.ensure_player_ihs_profile(v_uid);

  select sport into v_primary_sport
  from public.player_disciplines
  where player_id = v_uid
  order by is_primary desc, created_at asc
  limit 1;

  if v_primary_sport is not null then
    v_current := public.ensure_player_ihs_rating(v_uid, v_primary_sport);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'sport', r.sport,
    'sport_key', r.sport_key,
    'rating', r.rating,
    'level', r.level,
    'handicap', r.handicap,
    'verified_matches', r.verified_matches,
    'wins', r.wins,
    'losses', r.losses,
    'last_match_at', r.last_match_at
  ) order by r.updated_at desc), '[]'::jsonb)
  into v_ratings
  from public.player_ihs_ratings r
  where r.player_id = v_uid;

  return jsonb_build_object(
    'player_id', v_uid,
    'plan', coalesce(v_plan,'free'),
    'primary_sport', v_primary_sport,
    'current', case when v_current.id is not null then jsonb_build_object(
      'sport', v_current.sport,
      'sport_key', v_current.sport_key,
      'rating', v_current.rating,
      'level', v_current.level,
      'handicap', v_current.handicap,
      'verified_matches', v_current.verified_matches,
      'wins', v_current.wins,
      'losses', v_current.losses,
      'last_match_at', v_current.last_match_at
    ) else jsonb_build_object(
      'sport', null,
      'sport_key', null,
      'rating', v_default,
      'level', public.ihs_level_for_rating(v_default),
      'handicap', '{}'::jsonb,
      'verified_matches', 0,
      'wins', 0,
      'losses', 0,
      'last_match_at', null
    ) end,
    'ratings', v_ratings
  );
end;
$$;

create or replace function public.get_ihs_player_directory(p_sport text)
returns table(
  player_id uuid,
  full_name text,
  avatar_url text,
  ihs_rating numeric,
  ihs_level text,
  ihs_verified_matches integer,
  ihs_handicap jsonb
)
language sql
security definer
set search_path = public, pg_temp
as $$
  with base as (
    select p.id, p.full_name, p.avatar_url,
           coalesce(ip.default_rating, 2.50)::numeric as default_rating
    from public.profiles p
    left join public.player_ihs_profiles ip on ip.player_id = p.id
    where p.role::text = 'player' and p.full_name is not null
  )
  select b.id,
         b.full_name,
         b.avatar_url,
         coalesce(r.rating, b.default_rating)::numeric,
         coalesce(r.level, public.ihs_level_for_rating(b.default_rating)),
         coalesce(r.verified_matches,0),
         coalesce(r.handicap,'{}'::jsonb)
  from base b
  left join public.player_ihs_ratings r
    on r.player_id = b.id
   and r.sport_key = public.normalize_ihs_sport(p_sport)
  order by b.full_name;
$$;

create or replace function public.check_tournament_ihs_eligibility(p_tournament_id uuid, p_player_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_sport text;
  v_allowed text[];
  v_rating public.player_ihs_ratings;
begin
  select sport, ihs_allowed_categories into v_sport, v_allowed
  from public.tournaments where id = p_tournament_id;

  if not found then
    raise exception 'Tournament not found';
  end if;

  v_rating := public.ensure_player_ihs_rating(p_player_id, v_sport);

  return jsonb_build_object(
    'eligible', v_rating.level = any(v_allowed),
    'rating', v_rating.rating,
    'level', v_rating.level,
    'sport', v_rating.sport,
    'verified_matches', v_rating.verified_matches,
    'allowed_categories', to_jsonb(v_allowed)
  );
end;
$$;

grant execute on function public.get_my_ihs_overview() to authenticated;
grant execute on function public.get_ihs_player_directory(text) to authenticated;
grant execute on function public.check_tournament_ihs_eligibility(uuid,uuid) to authenticated;

-- Backfill IHS base profiles and known sport rows for existing player accounts.
insert into public.player_ihs_profiles(player_id)
select p.id from public.profiles p where p.role::text='player'
on conflict(player_id) do nothing;

insert into public.player_ihs_ratings(player_id, sport_key, sport, rating)
select distinct pd.player_id,
       public.normalize_ihs_sport(pd.sport),
       pd.sport,
       coalesce(ip.default_rating,2.50)
from public.player_disciplines pd
join public.profiles p on p.id=pd.player_id and p.role::text='player'
left join public.player_ihs_profiles ip on ip.player_id=pd.player_id
where public.normalize_ihs_sport(pd.sport) is not null
on conflict(player_id,sport_key) do nothing;

