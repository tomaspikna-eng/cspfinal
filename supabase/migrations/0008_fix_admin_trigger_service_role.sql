-- ============================================================================
-- CSP Database — Migration 0008: Allow service_role through the
-- admin-only-columns protection trigger
-- ============================================================================
-- Fixes a gap in protect_admin_only_columns() (migration 0001): BEFORE
-- UPDATE triggers fire for every caller regardless of role, unlike RLS
-- policies. That meant even the service_role key -- the role any future
-- backend automation (e.g. a billing webhook applying a plan after
-- payment) authenticates as -- was silently blocked from ever changing
-- plan/is_admin/plan_updated_at/plan_source, the same as a regular
-- non-admin user. This migration adds an explicit service_role bypass,
-- alongside the existing admin bypass, while leaving the protection for
-- regular authenticated non-admin users completely unchanged.
--
-- Uses `CREATE OR REPLACE FUNCTION` rather than the drop-then-create
-- pattern used elsewhere in this migration set: this only replaces the
-- body of an existing function with the same name/signature, so there's
-- no fresh-vs-existing table/type ambiguity to guard against, and the
-- trigger that already references this function by name picks up the
-- new behavior automatically -- no need to touch the trigger itself.
-- ============================================================================

create or replace function public.protect_admin_only_columns()
returns trigger
language plpgsql
as $$
declare
  v_privileged boolean;
begin
  -- service_role (backend automation) or an admin may change these
  -- columns freely. auth.role() reads the JWT `role` claim PostgREST
  -- sets for the request; it's null (not an error) for connections with
  -- no JWT context, so this stays false rather than blowing up there.
  v_privileged := (auth.role() = 'service_role') or public.is_admin(auth.uid());

  if not v_privileged then
    new.plan := old.plan;
    new.is_admin := old.is_admin;
    new.plan_updated_at := old.plan_updated_at;
    new.plan_source := old.plan_source;
  elsif new.plan is distinct from old.plan or new.plan_source is distinct from old.plan_source then
    -- Either service_role or an admin actually changed the plan: stamp
    -- plan_updated_at automatically, same convenience as before.
    new.plan_updated_at := now();
  end if;

  return new;
end;
$$;

comment on function public.protect_admin_only_columns() is
  'Blocks non-admin, non-service_role callers from changing plan/is_admin/plan_updated_at/plan_source on their own profile row. service_role (backend automation) and admins may change these on any row. Updated in migration 0008 to add the service_role bypass -- BEFORE UPDATE triggers apply to every role, so without it even the service_role key was blocked, same as any other non-admin caller.';
