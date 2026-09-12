alter table public.profiles add column if not exists cover_url text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('profile-covers','profile-covers',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=true,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'];

drop policy if exists "profile_covers_insert_own" on storage.objects;
create policy "profile_covers_insert_own" on storage.objects for insert to authenticated
with check (bucket_id='profile-covers' and (storage.foldername(name))[1]=auth.uid()::text);

drop policy if exists "profile_covers_update_own" on storage.objects;
create policy "profile_covers_update_own" on storage.objects for update to authenticated
using (bucket_id='profile-covers' and (storage.foldername(name))[1]=auth.uid()::text)
with check (bucket_id='profile-covers' and (storage.foldername(name))[1]=auth.uid()::text);

drop policy if exists "profile_covers_delete_own" on storage.objects;
create policy "profile_covers_delete_own" on storage.objects for delete to authenticated
using (bucket_id='profile-covers' and (storage.foldername(name))[1]=auth.uid()::text);

