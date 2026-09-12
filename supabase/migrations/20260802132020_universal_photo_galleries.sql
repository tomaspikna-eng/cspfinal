
create schema if not exists private;

create table public.gallery_collections (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  entity_type text not null check (entity_type in ('club','tournament','league','event','profile')),
  entity_id uuid not null,
  title text not null check (char_length(btrim(title)) between 1 and 120),
  description text,
  visibility text not null default 'private' check (visibility in ('private','public')),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (entity_type, entity_id, id)
);

comment on table public.gallery_collections is
  'Universal photo galleries attached to clubs, tournaments, leagues, events, or user profiles.';
comment on column public.gallery_collections.entity_id is
  'Polymorphic target validated by private.validate_gallery_collection_target().';

create table public.gallery_images (
  id uuid primary key default gen_random_uuid(),
  gallery_id uuid not null references public.gallery_collections(id) on delete cascade,
  uploader_id uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  storage_path text not null unique,
  caption text check (caption is null or char_length(caption) <= 500),
  alt_text text check (alt_text is null or char_length(alt_text) <= 250),
  sort_order integer not null default 0 check (sort_order >= 0),
  width integer check (width is null or width > 0),
  height integer check (height is null or height > 0),
  mime_type text check (mime_type is null or mime_type in ('image/jpeg','image/png','image/webp','image/avif')),
  size_bytes bigint check (size_bytes is null or size_bytes between 1 and 10485760),
  is_published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.gallery_images is
  'Metadata for files stored in the private gallery-images Storage bucket.';
comment on column public.gallery_images.storage_path is
  'Required format: {owner_id}/{gallery_id}/{unique_filename.ext}.';

create index gallery_collections_entity_idx
  on public.gallery_collections(entity_type, entity_id, visibility, published_at);
create index gallery_collections_owner_idx
  on public.gallery_collections(owner_id, created_at desc);
create index gallery_images_gallery_order_idx
  on public.gallery_images(gallery_id, sort_order, created_at);
create index gallery_images_public_idx
  on public.gallery_images(gallery_id, sort_order)
  where is_published;

create or replace function private.validate_gallery_collection_target()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  allowed boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  new.owner_id := auth.uid();

  case new.entity_type
    when 'club' then
      select exists (
        select 1 from public.clubs c
        where c.id = new.entity_id and c.owner_id = auth.uid()
      ) into allowed;
    when 'tournament' then
      select exists (
        select 1 from public.tournaments t
        where t.id = new.entity_id and t.owner_id = auth.uid()
      ) into allowed;
    when 'league' then
      select exists (
        select 1 from public.leagues l
        where l.id = new.entity_id
          and (l.owner_id = auth.uid() or public.can_manage_league(l.id))
      ) into allowed;
    when 'event' then
      select exists (
        select 1 from public.events e
        where e.id = new.entity_id and e.owner_id = auth.uid()
      ) into allowed;
    when 'profile' then
      allowed := new.entity_id = auth.uid();
  end case;

  if not allowed and not public.is_admin(auth.uid()) then
    raise exception 'You cannot create or move a gallery for this target';
  end if;

  return new;
end;
$$;

revoke all on function private.validate_gallery_collection_target() from public, anon, authenticated;

create trigger validate_gallery_collection_target
before insert or update of owner_id, entity_type, entity_id
on public.gallery_collections
for each row execute function private.validate_gallery_collection_target();

create or replace function private.validate_gallery_image()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  gallery_owner uuid;
  expected_prefix text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select g.owner_id into gallery_owner
  from public.gallery_collections g
  where g.id = new.gallery_id;

  if gallery_owner is null or (gallery_owner <> auth.uid() and not public.is_admin(auth.uid())) then
    raise exception 'You cannot add or move an image in this gallery';
  end if;

  expected_prefix := gallery_owner::text || '/' || new.gallery_id::text || '/';
  if left(new.storage_path, char_length(expected_prefix)) <> expected_prefix
     or new.storage_path ~ '(^|/)\.\.(/|$)' then
    raise exception 'Invalid gallery storage path';
  end if;

  new.uploader_id := auth.uid();
  return new;
end;
$$;

revoke all on function private.validate_gallery_image() from public, anon, authenticated;

create trigger validate_gallery_image
before insert or update of gallery_id, uploader_id, storage_path
on public.gallery_images
for each row execute function private.validate_gallery_image();

create or replace function private.touch_gallery_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function private.touch_gallery_updated_at() from public, anon, authenticated;

create trigger gallery_collections_touch_updated_at
before update on public.gallery_collections
for each row execute function private.touch_gallery_updated_at();

create trigger gallery_images_touch_updated_at
before update on public.gallery_images
for each row execute function private.touch_gallery_updated_at();

alter table public.gallery_collections enable row level security;
alter table public.gallery_images enable row level security;

grant select on public.gallery_collections, public.gallery_images to anon;
grant select, insert, update, delete on public.gallery_collections, public.gallery_images to authenticated;

create policy gallery_collections_public_read
on public.gallery_collections
for select
to anon, authenticated
using (visibility = 'public' and published_at is not null);

create policy gallery_collections_owner_read
on public.gallery_collections
for select
to authenticated
using (owner_id = (select auth.uid()) or public.is_admin((select auth.uid())));

create policy gallery_collections_owner_insert
on public.gallery_collections
for insert
to authenticated
with check (owner_id = (select auth.uid()) or public.is_admin((select auth.uid())));

create policy gallery_collections_owner_update
on public.gallery_collections
for update
to authenticated
using (owner_id = (select auth.uid()) or public.is_admin((select auth.uid())))
with check (owner_id = (select auth.uid()) or public.is_admin((select auth.uid())));

create policy gallery_collections_owner_delete
on public.gallery_collections
for delete
to authenticated
using (owner_id = (select auth.uid()) or public.is_admin((select auth.uid())));

create policy gallery_images_public_read
on public.gallery_images
for select
to anon, authenticated
using (
  is_published
  and exists (
    select 1 from public.gallery_collections g
    where g.id = gallery_images.gallery_id
      and g.visibility = 'public'
      and g.published_at is not null
  )
);

create policy gallery_images_owner_read
on public.gallery_images
for select
to authenticated
using (
  exists (
    select 1 from public.gallery_collections g
    where g.id = gallery_images.gallery_id
      and (g.owner_id = (select auth.uid()) or public.is_admin((select auth.uid())))
  )
);

create policy gallery_images_owner_insert
on public.gallery_images
for insert
to authenticated
with check (
  uploader_id = (select auth.uid())
  and exists (
    select 1 from public.gallery_collections g
    where g.id = gallery_images.gallery_id
      and (g.owner_id = (select auth.uid()) or public.is_admin((select auth.uid())))
  )
);

create policy gallery_images_owner_update
on public.gallery_images
for update
to authenticated
using (
  exists (
    select 1 from public.gallery_collections g
    where g.id = gallery_images.gallery_id
      and (g.owner_id = (select auth.uid()) or public.is_admin((select auth.uid())))
  )
)
with check (
  exists (
    select 1 from public.gallery_collections g
    where g.id = gallery_images.gallery_id
      and (g.owner_id = (select auth.uid()) or public.is_admin((select auth.uid())))
  )
);

create policy gallery_images_owner_delete
on public.gallery_images
for delete
to authenticated
using (
  exists (
    select 1 from public.gallery_collections g
    where g.id = gallery_images.gallery_id
      and (g.owner_id = (select auth.uid()) or public.is_admin((select auth.uid())))
  )
);

insert into storage.buckets (
  id, name, public, avif_autodetection, file_size_limit, allowed_mime_types
)
values (
  'gallery-images',
  'gallery-images',
  false,
  true,
  10485760,
  array['image/jpeg','image/png','image/webp','image/avif']
)
on conflict (id) do update
set public = excluded.public,
    avif_autodetection = excluded.avif_autodetection,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy gallery_storage_insert_own
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'gallery-images'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and exists (
    select 1 from public.gallery_collections g
    where g.id::text = (storage.foldername(name))[2]
      and g.owner_id = (select auth.uid())
  )
);

create policy gallery_storage_select
on storage.objects
for select
to anon, authenticated
using (
  bucket_id = 'gallery-images'
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or exists (
      select 1
      from public.gallery_images gi
      join public.gallery_collections g on g.id = gi.gallery_id
      where gi.storage_path = storage.objects.name
        and gi.is_published
        and g.visibility = 'public'
        and g.published_at is not null
    )
  )
);

create policy gallery_storage_update_own
on storage.objects
for update
to authenticated
using (
  bucket_id = 'gallery-images'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'gallery-images'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy gallery_storage_delete_own
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'gallery-images'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

