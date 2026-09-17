-- Allow the authenticated profile owner to read and update the location
-- columns introduced for the PRO+ editor. Row ownership remains enforced by
-- the existing profiles_select_authenticated and profiles_update_own policies.

grant select (city, country_code)
on public.profiles
to authenticated;

grant update (city, country_code)
on public.profiles
to authenticated;
