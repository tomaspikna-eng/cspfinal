insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('event-covers', 'event-covers', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "event_covers_upload_own" on storage.objects;
create policy "event_covers_upload_own"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'event-covers'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "event_covers_update_own" on storage.objects;
create policy "event_covers_update_own"
on storage.objects for update
to authenticated
using (
  bucket_id = 'event-covers'
  and owner_id = auth.uid()::text
)
with check (
  bucket_id = 'event-covers'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "event_covers_delete_own" on storage.objects;
create policy "event_covers_delete_own"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'event-covers'
  and owner_id = auth.uid()::text
);

