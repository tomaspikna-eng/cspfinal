
create or replace function public.get_my_profile_route()
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(
    (
      select case
        when p.is_admin
          or p.role in ('club'::public.profile_role, 'organization'::public.profile_role)
          then '/profil-ul/'
        else '/profil/'
      end
      from public.profiles p
      where p.id = (select auth.uid())
    ),
    '/profil/'
  );
$$;

comment on function public.get_my_profile_route() is
  'Canonical authenticated profile frontend route. Admin, club and organization -> /profil-ul/; non-admin player -> /profil/. Subscription plan is intentionally ignored.';

revoke all on function public.get_my_profile_route() from public;
revoke all on function public.get_my_profile_route() from anon;
grant execute on function public.get_my_profile_route() to authenticated;

