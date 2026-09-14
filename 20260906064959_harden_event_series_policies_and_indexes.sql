
create index if not exists event_series_club_idx
  on public.event_series(club_id)
  where club_id is not null;

drop policy if exists event_series_public_select on public.event_series;
drop policy if exists event_series_owner_all on public.event_series;

create policy event_series_public_select
  on public.event_series
  for select
  to anon
  using (status='published' and visibility='public');

create policy event_series_authenticated_select
  on public.event_series
  for select
  to authenticated
  using (
    owner_id=(select auth.uid())
    or (status='published' and visibility='public')
  );

create policy event_series_owner_insert
  on public.event_series
  for insert
  to authenticated
  with check (
    owner_id=(select auth.uid())
    and (
      club_id is null
      or exists(
        select 1 from public.clubs c
        where c.id=event_series.club_id
          and c.owner_id=(select auth.uid())
      )
    )
  );

create policy event_series_owner_update
  on public.event_series
  for update
  to authenticated
  using (owner_id=(select auth.uid()))
  with check (
    owner_id=(select auth.uid())
    and (
      club_id is null
      or exists(
        select 1 from public.clubs c
        where c.id=event_series.club_id
          and c.owner_id=(select auth.uid())
      )
    )
  );

create policy event_series_owner_delete
  on public.event_series
  for delete
  to authenticated
  using (owner_id=(select auth.uid()));

