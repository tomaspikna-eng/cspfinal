
drop policy gallery_collections_public_read on public.gallery_collections;
drop policy gallery_collections_owner_read on public.gallery_collections;

create policy gallery_collections_read
on public.gallery_collections
for select
to anon, authenticated
using (
  (visibility = 'public' and published_at is not null)
  or owner_id = (select auth.uid())
  or public.is_admin((select auth.uid()))
);

drop policy gallery_images_public_read on public.gallery_images;
drop policy gallery_images_owner_read on public.gallery_images;

create policy gallery_images_read
on public.gallery_images
for select
to anon, authenticated
using (
  (
    is_published
    and exists (
      select 1 from public.gallery_collections g
      where g.id = gallery_images.gallery_id
        and g.visibility = 'public'
        and g.published_at is not null
    )
  )
  or exists (
    select 1 from public.gallery_collections g
    where g.id = gallery_images.gallery_id
      and (
        g.owner_id = (select auth.uid())
        or public.is_admin((select auth.uid()))
      )
  )
);

