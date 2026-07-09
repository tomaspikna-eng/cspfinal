-- Migration 0014: Article categories (Novinky, Recenzie, História, Pravidlá hry)
-- Matches the 4 categories already styled on the public magazine page
-- (magazin/index.html's --c-novinky/--c-recenzie/--c-historia/--c-pravidla).
-- Adds a real category column so the CMS editor and the public magazine
-- can both read/write the same real data instead of a hardcoded/missing
-- concept.

alter table articles
  add column category text not null default 'novinky'
  check (category in ('novinky','recenzie','historia','pravidla'));

comment on column articles.category is 'novinky = news, recenzie = reviews, historia = history, pravidla = rules/how-to. Matches public magazine page categories exactly.';

create index if not exists articles_category_status_published_idx
  on articles(category, status, published_at desc);
