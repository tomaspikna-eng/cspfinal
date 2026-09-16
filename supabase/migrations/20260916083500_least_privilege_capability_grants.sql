-- Connect Sports Pro — least-privilege cleanup after 2026-09-16 audit
-- Remove table-level INSERT/UPDATE grants that implicitly include bearer
-- capability columns, then restore write access only to non-secret columns.

do $acl$
declare
  v_columns text;
begin
  -- matches: owners/participants may keep their existing RLS-governed write
  -- paths, but browser roles must never choose or rotate public_token directly.
  revoke insert, update on table public.matches from authenticated;

  select string_agg(quote_ident(a.attname), ', ' order by a.attnum)
    into v_columns
  from pg_catalog.pg_attribute a
  where a.attrelid = 'public.matches'::regclass
    and a.attnum > 0
    and not a.attisdropped
    and a.attname <> 'public_token';

  execute 'grant insert (' || v_columns || ') on table public.matches to authenticated';
  execute 'grant update (' || v_columns || ') on table public.matches to authenticated';

  -- tournament resources: device_token is generated/rotated server-side only.
  revoke insert, update on table public.tournament_resources from authenticated;

  select string_agg(quote_ident(a.attname), ', ' order by a.attnum)
    into v_columns
  from pg_catalog.pg_attribute a
  where a.attrelid = 'public.tournament_resources'::regclass
    and a.attnum > 0
    and not a.attisdropped
    and a.attname <> 'device_token';

  execute 'grant insert (' || v_columns || ') on table public.tournament_resources to authenticated';
  execute 'grant update (' || v_columns || ') on table public.tournament_resources to authenticated';
end;
$acl$;

-- Profiles are created by the auth trigger. Browser clients never need direct
-- INSERT access, particularly not to email/is_admin/billing-owned fields.
revoke insert on table public.profiles from authenticated;
