create table if not exists public.profile_follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  following_profile_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_profile_id),
  constraint profile_follows_no_self check (follower_id <> following_profile_id)
);

create index if not exists profile_follows_following_idx on public.profile_follows(following_profile_id, created_at desc);
create index if not exists profile_follows_follower_idx on public.profile_follows(follower_id, created_at desc);

create table if not exists public.social_reactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  entity_type text not null,
  entity_id uuid not null,
  reaction_type text not null default 'respect',
  created_at timestamptz not null default now(),
  constraint social_reactions_entity_type_check check (entity_type in ('profile','event','tournament','training_session','gallery_collection','gallery_image')),
  constraint social_reactions_reaction_type_check check (reaction_type = 'respect'),
  unique (user_id, entity_type, entity_id, reaction_type)
);

create index if not exists social_reactions_entity_idx on public.social_reactions(entity_type, entity_id, reaction_type, created_at desc);
create index if not exists social_reactions_user_idx on public.social_reactions(user_id, created_at desc);

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
  read_at timestamptz,
  constraint notifications_type_check check (notification_type in ('new_follower','profile_respect'))
);

create index if not exists notifications_recipient_idx on public.notifications(recipient_id, is_read, created_at desc);

alter table public.profile_follows enable row level security;
alter table public.social_reactions enable row level security;
alter table public.notifications enable row level security;

drop policy if exists "profile follows public read" on public.profile_follows;
create policy "profile follows public read" on public.profile_follows for select using (true);
drop policy if exists "profile follows insert own" on public.profile_follows;
create policy "profile follows insert own" on public.profile_follows for insert with check (auth.uid() = follower_id);
drop policy if exists "profile follows delete own" on public.profile_follows;
create policy "profile follows delete own" on public.profile_follows for delete using (auth.uid() = follower_id);

drop policy if exists "social reactions public read" on public.social_reactions;
create policy "social reactions public read" on public.social_reactions for select using (true);
drop policy if exists "social reactions insert own" on public.social_reactions;
create policy "social reactions insert own" on public.social_reactions for insert with check (auth.uid() = user_id);
drop policy if exists "social reactions delete own" on public.social_reactions;
create policy "social reactions delete own" on public.social_reactions for delete using (auth.uid() = user_id);

drop policy if exists "notifications read own" on public.notifications;
create policy "notifications read own" on public.notifications for select using (auth.uid() = recipient_id);
drop policy if exists "notifications update own" on public.notifications;
create policy "notifications update own" on public.notifications for update using (auth.uid() = recipient_id) with check (auth.uid() = recipient_id);

create or replace function public.create_follow_notification()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.notifications(recipient_id, actor_id, notification_type, entity_type, entity_id, title, body)
  values (new.following_profile_id, new.follower_id, 'new_follower', 'profile', new.following_profile_id, 'Nový sledovateľ', 'Niekto začal sledovať tvoj profil.');
  return new;
end;
$$;

drop trigger if exists trg_profile_follow_notification on public.profile_follows;
create trigger trg_profile_follow_notification after insert on public.profile_follows for each row execute function public.create_follow_notification();

create or replace function public.create_profile_respect_notification()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.entity_type = 'profile' and new.entity_id <> new.user_id then
    insert into public.notifications(recipient_id, actor_id, notification_type, entity_type, entity_id, title, body)
    values (new.entity_id, new.user_id, 'profile_respect', 'profile', new.entity_id, 'Nový rešpekt', 'Niekto dal rešpekt tvojmu profilu.');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_profile_respect_notification on public.social_reactions;
create trigger trg_profile_respect_notification after insert on public.social_reactions for each row execute function public.create_profile_respect_notification();

create or replace function public.get_profile_social_state(p_profile_id uuid)
returns table(following_count bigint, followers_count bigint, respect_count bigint, viewer_follows boolean, viewer_respected boolean)
language sql stable security definer set search_path=public as $$
  select
    (select count(*) from public.profile_follows where follower_id=p_profile_id),
    (select count(*) from public.profile_follows where following_profile_id=p_profile_id),
    (select count(*) from public.social_reactions where entity_type='profile' and entity_id=p_profile_id and reaction_type='respect'),
    exists(select 1 from public.profile_follows where follower_id=auth.uid() and following_profile_id=p_profile_id),
    exists(select 1 from public.social_reactions where user_id=auth.uid() and entity_type='profile' and entity_id=p_profile_id and reaction_type='respect');
$$;
grant execute on function public.get_profile_social_state(uuid) to anon, authenticated;

create or replace function public.mark_all_notifications_read()
returns integer language plpgsql security definer set search_path=public as $$
declare n integer;
begin
  update public.notifications set is_read=true, read_at=coalesce(read_at,now()) where recipient_id=auth.uid() and is_read=false;
  get diagnostics n = row_count;
  return n;
end;
$$;
grant execute on function public.mark_all_notifications_read() to authenticated;

