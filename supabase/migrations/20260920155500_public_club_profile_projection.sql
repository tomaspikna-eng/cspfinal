create or replace function public.get_public_club_profile(p_owner_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_profile jsonb;
  v_club jsonb;
  v_public jsonb;
  v_venues jsonb;
  v_tournaments jsonb;
  v_events jsonb;
begin
  select jsonb_build_object(
      'id',p.id,
      'full_name',p.full_name,
      'avatar_url',p.avatar_url,
      'bio',p.bio,
      'created_at',p.created_at
    ),
    jsonb_build_object(
      'id',c.id,
      'name',c.name,
      'created_at',c.created_at,
      'address_line1',c.address_line1,
      'postal_code',c.postal_code,
      'city',c.city,
      'country',c.country,
      'opening_hours',c.opening_hours
    )
  into v_profile,v_club
  from public.profiles p
  join public.clubs c on c.owner_id=p.id
  where p.id=p_owner_id
    and p.role::text in ('club','organization')
  order by c.created_at asc
  limit 1;

  if v_club is null then return null; end if;

  select case when cpp.club_id is null then null else jsonb_build_object(
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
  into v_public
  from public.clubs c
  left join public.club_public_profiles cpp on cpp.club_id=c.id and cpp.status='published'
  where c.id=(v_club->>'id')::uuid;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',v.id,'name',v.name,'sport',v.sport,'description',v.description,'is_active',v.is_active
  ) order by v.created_at),'[]'::jsonb)
  into v_venues
  from public.venues v
  where v.club_id=(v_club->>'id')::uuid and v.is_active;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',t.id,'name',t.name,'sport',t.sport,'discipline',t.discipline,'date',t.date,'status',t.status
  ) order by t.date desc nulls last),'[]'::jsonb)
  into v_tournaments
  from (
    select *
    from public.tournaments t
    where t.owner_id=p_owner_id
      and coalesce(t.visibility,'public')='public'
      and coalesce(t.status,'')<>'draft'
    order by t.date desc nulls last
    limit 8
  ) t;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',e.id,'title',e.title,'sport',e.sport,'event_type',e.event_type,'starts_at',e.starts_at,'status',e.status
  ) order by e.starts_at desc nulls last),'[]'::jsonb)
  into v_events
  from (
    select *
    from public.events e
    where (e.club_id=(v_club->>'id')::uuid or e.owner_id=p_owner_id)
      and coalesce(e.visibility,'public')='public'
      and coalesce(e.status,'published') not in ('draft','cancelled')
    order by e.starts_at desc nulls last
    limit 8
  ) e;

  return jsonb_build_object(
    'profile',v_profile,
    'club',v_club,
    'public_profile',v_public,
    'venues',coalesce(v_venues,'[]'::jsonb),
    'tournaments',coalesce(v_tournaments,'[]'::jsonb),
    'events',coalesce(v_events,'[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_public_club_profile(uuid) from public;
grant execute on function public.get_public_club_profile(uuid) to anon, authenticated, service_role;