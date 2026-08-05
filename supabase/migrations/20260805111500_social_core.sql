-- CSP social core: follows, profile respect, generic likes and notifications.
-- Idempotent so it also repairs projects where the first profile-only social
-- tables were created outside this repository.

create table if not exists public.profile_follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  following_profile_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_profile_id),
  constraint profile_follows_no_self check (follower_id <> following_profile_id)
);

create table if not exists public.social_reactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  entity_type text not null,
  entity_id uuid not null,
  reaction_type text not null default 'like',
  created_at timestamptz not null default now(),
  unique (user_id, entity_type, entity_id, reaction_type)
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  notification_type text not null,
  entity_type text,
  entity_id uuid,
  title text not null,
  body text,
  is_read boolean not null default false,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

alter table public.social_reactions
  drop constraint if exists social_reactions_entity_type_check,
  drop constraint if exists social_reactions_reaction_type_check;
alter table public.social_reactions
  add constraint social_reactions_entity_type_check
    check (entity_type in ('profile','article','event','tournament','league','training_session','gallery_collection','gallery_image')),
  add constraint social_reactions_reaction_type_check
    check (reaction_type in ('like','respect'));

alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications
  add constraint notifications_type_check
    check (notification_type in ('new_follower','profile_respect'));

create index if not exists social_reactions_entity_idx
  on public.social_reactions (entity_type, entity_id, reaction_type);
create index if not exists social_reactions_user_idx
  on public.social_reactions (user_id, created_at desc);
create index if not exists profile_follows_following_idx
  on public.profile_follows (following_profile_id, created_at desc);
create index if not exists notifications_recipient_idx
  on public.notifications (recipient_id, is_read, created_at desc);

alter table public.profile_follows enable row level security;
alter table public.social_reactions enable row level security;
alter table public.notifications enable row level security;

drop policy if exists "profile follows public read" on public.profile_follows;
drop policy if exists "profile follows insert own" on public.profile_follows;
drop policy if exists "profile follows delete own" on public.profile_follows;
create policy "profile follows public read" on public.profile_follows
  for select to anon, authenticated using (true);
create policy "profile follows insert own" on public.profile_follows
  for insert to authenticated
  with check ((select auth.uid()) = follower_id);
create policy "profile follows delete own" on public.profile_follows
  for delete to authenticated
  using ((select auth.uid()) = follower_id);

drop policy if exists "social reactions public read" on public.social_reactions;
drop policy if exists "social reactions insert own" on public.social_reactions;
drop policy if exists "social reactions delete own" on public.social_reactions;
create policy "social reactions public read" on public.social_reactions
  for select to anon, authenticated using (true);
create policy "social reactions insert own" on public.social_reactions
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "social reactions delete own" on public.social_reactions
  for delete to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "notifications read own" on public.notifications;
drop policy if exists "notifications update own" on public.notifications;
create policy "notifications read own" on public.notifications
  for select to authenticated
  using ((select auth.uid()) = recipient_id);
create policy "notifications update own" on public.notifications
  for update to authenticated
  using ((select auth.uid()) = recipient_id)
  with check ((select auth.uid()) = recipient_id);

revoke all on public.profile_follows from anon, authenticated;
revoke all on public.social_reactions from anon, authenticated;
revoke all on public.notifications from anon, authenticated;
grant select on public.profile_follows, public.social_reactions to anon;
grant select, insert, delete on public.profile_follows, public.social_reactions to authenticated;
grant select, update on public.notifications to authenticated;
grant select, insert, update, delete on public.profile_follows, public.social_reactions, public.notifications to service_role;

create or replace function public.get_profile_social_state(p_profile_id uuid)
returns table(
  following_count bigint,
  followers_count bigint,
  respect_count bigint,
  viewer_follows boolean,
  viewer_respected boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    (select count(*) from public.profile_follows where follower_id = p_profile_id),
    (select count(*) from public.profile_follows where following_profile_id = p_profile_id),
    (select count(*) from public.social_reactions where entity_type = 'profile' and entity_id = p_profile_id and reaction_type = 'respect'),
    exists(select 1 from public.profile_follows where follower_id = (select auth.uid()) and following_profile_id = p_profile_id),
    exists(select 1 from public.social_reactions where user_id = (select auth.uid()) and entity_type = 'profile' and entity_id = p_profile_id and reaction_type = 'respect');
$$;

create or replace function public.mark_all_notifications_read()
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare affected integer;
begin
  update public.notifications
     set is_read = true, read_at = coalesce(read_at, now())
   where recipient_id = (select auth.uid()) and is_read = false;
  get diagnostics affected = row_count;
  return affected;
end;
$$;

revoke all on function public.get_profile_social_state(uuid) from public, anon, authenticated;
grant execute on function public.get_profile_social_state(uuid) to anon, authenticated;
revoke all on function public.mark_all_notifications_read() from public, anon, authenticated;
grant execute on function public.mark_all_notifications_read() to authenticated;

-- Notify a profile only for follows and profile respect. Generic likes remain
-- quiet, avoiding notification spam for articles, events and tournaments.
create schema if not exists private;

create or replace function private.create_follow_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.notifications(recipient_id, actor_id, notification_type, entity_type, entity_id, title, body)
  values (new.following_profile_id, new.follower_id, 'new_follower', 'profile', new.following_profile_id, 'Nový sledovateľ', 'Niekto začal sledovať tvoj profil.');
  return new;
end;
$$;

create or replace function private.create_profile_respect_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.entity_type = 'profile' and new.reaction_type = 'respect' and new.entity_id <> new.user_id then
    insert into public.notifications(recipient_id, actor_id, notification_type, entity_type, entity_id, title, body)
    values (new.entity_id, new.user_id, 'profile_respect', 'profile', new.entity_id, 'Nový rešpekt', 'Niekto udelil rešpekt tvojmu profilu.');
  end if;
  return new;
end;
$$;

revoke all on function private.create_follow_notification() from public, anon, authenticated;
revoke all on function private.create_profile_respect_notification() from public, anon, authenticated;

drop trigger if exists trg_profile_follow_notification on public.profile_follows;
create trigger trg_profile_follow_notification
after insert on public.profile_follows
for each row execute function private.create_follow_notification();

drop trigger if exists trg_profile_respect_notification on public.social_reactions;
create trigger trg_profile_respect_notification
after insert on public.social_reactions
for each row execute function private.create_profile_respect_notification();

notify pgrst, 'reload schema';
