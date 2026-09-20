-- Unified CSP public search + employee privacy hardening

create or replace function public.search_public_players(
  p_query text,
  p_limit integer default 20
)
returns table (
  id uuid,
  full_name text,
  role text,
  plan text,
  avatar_url text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    p.id,
    p.full_name,
    p.role::text,
    public.current_plan(p.id)::text,
    p.avatar_url
  from public.profiles p
  where p.role::text = 'player'
    and not exists (
      select 1
      from public.club_employees ce
      where ce.auth_user_id = p.id
    )
    and length(btrim(coalesce(p_query,''))) >= 2
    and p.full_name ilike '%' || replace(replace(btrim(p_query), '%', ''), '_', '') || '%'
  order by p.full_name asc
  limit least(greatest(coalesce(p_limit,20),1),20);
$$;

revoke all on function public.search_public_players(text,integer) from public;
grant execute on function public.search_public_players(text,integer) to anon, authenticated, service_role;

create or replace function public.search_public_entities(
  p_query text,
  p_limit integer default 12
)
returns table (
  entity_type text,
  id uuid,
  owner_id uuid,
  title text,
  subtitle text,
  meta text,
  image_url text,
  href text
)
language sql
stable
security definer
set search_path = ''
as $$
  with q as (
    select replace(replace(btrim(coalesce(p_query,'')), '%', ''), '_', '') as term,
           least(greatest(coalesce(p_limit,12),1),20) as lim
  ),
  players as (
    select
      'player'::text entity_type,
      p.id,
      p.id owner_id,
      p.full_name title,
      ('Hráč · ' || case when public.current_plan(p.id)::text='pro_plus' then 'PRO+' else upper(public.current_plan(p.id)::text) end)::text subtitle,
      null::text meta,
      p.avatar_url image_url,
      ('/profil/?id=' || p.id::text || '&view=public')::text href,
      row_number() over(order by p.full_name asc) rn
    from public.profiles p,q
    where length(q.term)>=2
      and p.role::text='player'
      and not exists (select 1 from public.club_employees ce where ce.auth_user_id=p.id)
      and p.full_name ilike '%'||q.term||'%'
  ),
  clubs as (
    select
      'club'::text entity_type,
      c.id,
      c.owner_id,
      c.name title,
      'Klub · ULTRA'::text subtitle,
      nullif(concat_ws(', ',c.city,c.country),'')::text meta,
      p.avatar_url image_url,
      ('/profil-ul/?id=' || c.owner_id::text || '&view=public')::text href,
      row_number() over(order by c.name asc) rn
    from public.clubs c
    join public.profiles p on p.id=c.owner_id
    cross join q
    where length(q.term)>=2
      and p.role::text in ('club','organization')
      and (
        c.name ilike '%'||q.term||'%'
        or coalesce(c.city,'') ilike '%'||q.term||'%'
        or coalesce(c.country,'') ilike '%'||q.term||'%'
      )
  ),
  tournaments as (
    select
      'tournament'::text entity_type,
      t.id,
      t.owner_id,
      t.name title,
      'Turnaj'::text subtitle,
      nullif(concat_ws(' · ',t.sport,t.discipline,t.city),'')::text meta,
      null::text image_url,
      ('/turnament/?id=' || t.id::text)::text href,
      row_number() over(order by coalesce(t.date,current_date) desc,t.name asc) rn
    from public.tournaments t
    cross join q
    where length(q.term)>=2
      and coalesce(t.visibility,'public')='public'
      and coalesce(t.status,'') <> 'draft'
      and (
        t.name ilike '%'||q.term||'%'
        or coalesce(t.sport,'') ilike '%'||q.term||'%'
        or coalesce(t.discipline,'') ilike '%'||q.term||'%'
        or coalesce(t.city,'') ilike '%'||q.term||'%'
      )
  ),
  events as (
    select
      'event'::text entity_type,
      e.id,
      e.owner_id,
      e.title,
      'Udalosť'::text subtitle,
      nullif(concat_ws(' · ',e.event_type,e.sport,e.city),'')::text meta,
      e.cover_image_url image_url,
      ('/udalost/?id=' || e.id::text)::text href,
      row_number() over(order by coalesce(e.starts_at,e.created_at) desc,e.title asc) rn
    from public.events e
    cross join q
    where length(q.term)>=2
      and coalesce(e.visibility,'public')='public'
      and coalesce(e.status,'published') not in ('draft','cancelled')
      and (
        e.title ilike '%'||q.term||'%'
        or coalesce(e.event_type,'') ilike '%'||q.term||'%'
        or coalesce(e.sport,'') ilike '%'||q.term||'%'
        or coalesce(e.discipline,'') ilike '%'||q.term||'%'
        or coalesce(e.city,'') ilike '%'||q.term||'%'
      )
  )
  select entity_type,id,owner_id,title,subtitle,meta,image_url,href
  from (
    select * from players
    union all select * from clubs
    union all select * from tournaments
    union all select * from events
  ) x,q
  where x.rn<=q.lim
  order by
    case x.entity_type when 'club' then 1 when 'player' then 2 when 'tournament' then 3 else 4 end,
    x.title asc;
$$;

comment on function public.search_public_entities(text,integer) is
  'Unified public CSP search for players, clubs, tournaments and events. Employee-linked auth users are excluded from player results.';

revoke all on function public.search_public_entities(text,integer) from public;
grant execute on function public.search_public_entities(text,integer) to anon, authenticated, service_role;

create or replace function public.get_public_club_profile(p_owner_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'profile', jsonb_build_object(
      'id',p.id,
      'full_name',p.full_name,
      'avatar_url',p.avatar_url,
      'bio',p.bio,
      'created_at',p.created_at
    ),
    'club', jsonb_build_object(
      'id',c.id,
      'name',c.name,
      'created_at',c.created_at,
      'address_line1',c.address_line1,
      'postal_code',c.postal_code,
      'city',c.city,
      'country',c.country,
      'opening_hours',c.opening_hours
    ),
    'public_profile', case when cpp.club_id is null then null else jsonb_build_object(
      'about_title',cpp.about_title,
      'about_text',cpp.about_text,
      'offer_text',cpp.offer_text,
      'contact_text',cpp.contact_text,
      'history_text',cpp.history_text,
      'photo_url',cpp.photo_url,
      'reservations_visible',cpp.reservations_visible,
      'events_visible',cpp.events_visible,
      'representatives_visible',cpp.representatives_visible,
      'gallery_visible',cpp.gallery_visible
    ) end
  )
  from public.profiles p
  join public.clubs c on c.owner_id=p.id
  left join public.club_public_profiles cpp on cpp.club_id=c.id and cpp.status='published'
  where p.id=p_owner_id
    and p.role::text in ('club','organization')
  order by c.created_at asc
  limit 1;
$$;

revoke all on function public.get_public_club_profile(uuid) from public;
grant execute on function public.get_public_club_profile(uuid) to anon, authenticated, service_role;
