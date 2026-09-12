
create or replace function public.create_magazine_draft(
  p_author_id uuid,
  p_title text,
  p_slug text,
  p_category text,
  p_excerpt text,
  p_content text,
  p_cover_image_url text default null
)
returns table (
  article_id uuid,
  article_slug text,
  created boolean
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_title text := btrim(coalesce(p_title, ''));
  v_slug text := lower(btrim(coalesce(p_slug, '')));
  v_category text := lower(btrim(coalesce(p_category, '')));
  v_content text := btrim(coalesce(p_content, ''));
  v_existing_id uuid;
  v_article_id uuid;
begin
  if not exists (
    select 1
    from public.profiles p
    where p.id = p_author_id
      and p.is_admin = true
  ) then
    raise exception using
      errcode = '42501',
      message = 'author_id must belong to a CSP magazine administrator';
  end if;

  if v_title = '' then
    raise exception using errcode = '22023', message = 'title is required';
  end if;

  if v_content = '' then
    raise exception using errcode = '22023', message = 'content is required';
  end if;

  if v_category not in ('novinky', 'recenzie', 'historia', 'pravidla', 'navody') then
    raise exception using errcode = '22023', message = 'unsupported magazine category';
  end if;

  if length(v_slug) > 80 or v_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
    raise exception using
      errcode = '22023',
      message = 'slug must contain only lowercase ASCII letters, digits and hyphens';
  end if;

  if nullif(btrim(coalesce(p_cover_image_url, '')), '') is not null
     and btrim(p_cover_image_url) !~ '^https://[^[:space:]]+$' then
    raise exception using errcode = '22023', message = 'cover image must use an HTTPS URL';
  end if;

  select a.id
  into v_existing_id
  from public.articles a
  where a.slug = v_slug;

  if v_existing_id is not null then
    return query select v_existing_id, v_slug, false;
    return;
  end if;

  insert into public.articles (
    author_id,
    title,
    slug,
    category,
    excerpt,
    content,
    cover_image_url,
    status,
    published_at
  ) values (
    p_author_id,
    v_title,
    v_slug,
    v_category,
    nullif(btrim(coalesce(p_excerpt, '')), ''),
    v_content,
    nullif(btrim(coalesce(p_cover_image_url, '')), ''),
    'draft',
    null
  )
  returning id into v_article_id;

  return query select v_article_id, v_slug, true;
end;
$$;

revoke all on function public.create_magazine_draft(uuid, text, text, text, text, text, text)
  from public, anon, authenticated;

grant execute on function public.create_magazine_draft(uuid, text, text, text, text, text, text)
  to service_role;

comment on function public.create_magazine_draft(uuid, text, text, text, text, text, text) is
  'Creates an unpublished CSP Magazine draft for review. Existing slugs are returned without overwriting the article.';

