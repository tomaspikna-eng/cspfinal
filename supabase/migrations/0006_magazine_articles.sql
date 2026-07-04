-- ============================================================================
-- CSP Database — Migration 0006: Magazine — Articles (CMS)
-- Prompt 6 of 7 (builds on 0001-0005)
-- ============================================================================
-- Admin-only CMS, public read of published articles (including anonymous,
-- logged-out visitors — a public magazine is an SEO/content surface).
-- Write access is is_admin-gated via can_access_magazine_cms() from
-- prompt 2, not tied to plan tier and not per-author — any admin can
-- edit/unpublish any article. No categories/tags/comments/analytics yet.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. CLEAN SLATE
-- ----------------------------------------------------------------------------
-- articles is created by this migration itself, so — same lesson as 0001
-- and 0005 — no explicit `DROP TRIGGER ... ON public.articles` here (IF
-- EXISTS still requires the table to exist, which it won't on a fresh
-- run). `DROP TABLE ... CASCADE` below removes any triggers for free.
drop function if exists public.set_article_published_at() cascade;

drop table if exists public.articles cascade;

-- ----------------------------------------------------------------------------
-- 1. ARTICLES
-- ----------------------------------------------------------------------------
create table public.articles (
  id uuid primary key default gen_random_uuid(),
  author_id uuid references public.profiles(id) on delete set null,
  title text not null,
  slug text not null unique,
  excerpt text,
  content text not null,
  cover_image_url text,
  status text not null default 'draft' check (status in ('draft', 'published')),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.articles is
  'Magazine CMS articles. Write access is admin-only (can_access_magazine_cms), not per-author — any admin may edit/unpublish any article regardless of author_id. Published articles are publicly readable, including by anonymous visitors.';
comment on column public.articles.author_id is
  'Who wrote it, for display only. Nullable and ON DELETE SET NULL so deleting an admin account never deletes their articles.';
comment on column public.articles.content is
  'Article body. Markdown vs HTML is a frontend rendering concern; stored here as plain text either way.';
comment on column public.articles.cover_image_url is
  'Nullable; storage wiring (uploading the actual image) comes in prompt 7. This column is just reserved for it now.';
comment on column public.articles.published_at is
  'Set automatically the first time status becomes ''published'' (see set_article_published_at()); preserved as the original publish date through later edits, even if the article is unpublished and republished.';

-- slug's UNIQUE constraint above already provides its lookup index.
create index articles_status_published_at_idx on public.articles (status, published_at desc);

-- Reuses the shared updated_at stamper from 0001_auth_profiles.sql.
create trigger articles_set_updated_at
  before update on public.articles
  for each row execute function public.set_updated_at();

-- ----------------------------------------------------------------------------
-- 2. AUTO-MANAGE published_at
-- ----------------------------------------------------------------------------
-- Fires on INSERT too (an article can be created already-published in one
-- step), and only stamps when transitioning INTO 'published' for the
-- first time (guarded by published_at still being null) — later edits,
-- or a draft -> published -> draft -> published round trip, never
-- overwrite the original publish date.
create function public.set_article_published_at()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'published' and new.published_at is null then
    if tg_op = 'INSERT' or old.status is distinct from 'published' then
      new.published_at := now();
    end if;
  end if;

  return new;
end;
$$;

comment on function public.set_article_published_at() is
  'Stamps published_at = now() the first time status transitions to (or is created as) published. Never overwrites an existing published_at, so the original publish date survives later edits and unpublish/republish cycles.';

create trigger articles_set_published_at
  before insert or update on public.articles
  for each row execute function public.set_article_published_at();

-- ----------------------------------------------------------------------------
-- 3. ROW LEVEL SECURITY
-- ----------------------------------------------------------------------------
alter table public.articles enable row level security;

-- Public read of published articles — explicitly includes the anon role
-- so logged-out visitors can read the magazine, not just authenticated
-- users. A regular authenticated non-admin gets exactly this same access,
-- nothing more (no author-based or plan-based extra visibility).
create policy articles_select_published_public
  on public.articles
  for select
  to anon, authenticated
  using (status = 'published');

-- Admins (any admin, not just the article's own author) get full CRUD on
-- every row, drafts included. Reuses can_access_magazine_cms() from
-- prompt 2 rather than a new gating mechanism.
create policy articles_admin_all
  on public.articles
  for all
  to authenticated
  using (public.can_access_magazine_cms(auth.uid()))
  with check (public.can_access_magazine_cms(auth.uid()));

grant select on public.articles to anon, authenticated;
grant insert, update, delete on public.articles to authenticated;
