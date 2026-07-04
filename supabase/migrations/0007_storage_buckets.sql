-- ============================================================================
-- CSP Database — Migration 0007: Storage — Avatars & Article Covers
-- Prompt 7 of 7 (builds on 0001-0006) — final prompt in the initial
-- CSP Supabase backend sequence.
-- ============================================================================
-- Wires up real file storage for the two placeholder columns left by
-- earlier prompts: profiles.avatar_url (prompt 1) and
-- articles.cover_image_url (prompt 6). This migration only creates
-- buckets and storage.objects RLS policies — it does not touch the
-- profiles or articles tables; the frontend uploads a file, gets a public
-- URL back, and writes that URL into the existing column via a normal
-- table update, already covered by those tables' existing RLS.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. CLEAN SLATE
-- ----------------------------------------------------------------------------
-- storage.objects is a pre-existing Supabase system table (RLS already
-- enabled on it by default) — only the policies below belong to this
-- migration, so only they're dropped for a clean re-run. Buckets are
-- handled via ON CONFLICT DO NOTHING instead of a drop/recreate, so
-- existing files are never wiped out by re-running this migration.
drop policy if exists avatars_select_public on storage.objects;
drop policy if exists avatars_write_own on storage.objects;
drop policy if exists article_covers_select_public on storage.objects;
drop policy if exists article_covers_write_admin on storage.objects;

-- ----------------------------------------------------------------------------
-- 1. BUCKETS
-- ----------------------------------------------------------------------------
-- Both public (public read via their public URL); write access is
-- controlled entirely by the RLS policies on storage.objects below, not
-- by the bucket's public flag.
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('article-covers', 'article-covers', true)
on conflict (id) do nothing;

-- ----------------------------------------------------------------------------
-- 2. RLS — `avatars` BUCKET
-- ----------------------------------------------------------------------------
-- Expected upload path convention: avatars/{user_id}/{filename}
-- (storage.foldername(name))[1] is the first path segment under the
-- bucket, i.e. {user_id} — this is what's compared against auth.uid()
-- below to enforce "a user can only write inside their own folder."

create policy avatars_select_public
  on storage.objects
  for select
  to anon, authenticated
  using (bucket_id = 'avatars');

create policy avatars_write_own
  on storage.objects
  for all
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ----------------------------------------------------------------------------
-- 3. RLS — `article-covers` BUCKET
-- ----------------------------------------------------------------------------
-- Expected upload path convention: article-covers/{article_id}/{filename}
-- No ownership restriction is enforced on the path itself (unlike
-- avatars) — all admins share equal CMS access per prompt 6, so this is
-- just a sensible organisational convention, not something RLS needs to
-- check. Write access is gated purely by can_access_magazine_cms(),
-- reused unchanged from prompt 2.

create policy article_covers_select_public
  on storage.objects
  for select
  to anon, authenticated
  using (bucket_id = 'article-covers');

create policy article_covers_write_admin
  on storage.objects
  for all
  to authenticated
  using (
    bucket_id = 'article-covers'
    and public.can_access_magazine_cms(auth.uid())
  )
  with check (
    bucket_id = 'article-covers'
    and public.can_access_magazine_cms(auth.uid())
  );

-- ----------------------------------------------------------------------------
-- Not built here (flagged for later, not designed/requested yet):
-- - A club-logo bucket: clubs (prompt 5) has no logo_url column yet, so
--   there's nothing to wire storage to. Add both together in a future
--   prompt if/when a club logo feature is designed.
-- - File size / MIME-type restrictions beyond Supabase's platform
--   defaults, and image resizing/thumbnails (frontend/CDN concern, not a
--   database one).
-- ----------------------------------------------------------------------------
