-- Connect Sports Pro — immediate achievement feedback
-- Creates an in-app notification for every newly unlocked achievement.
-- The existing generic notification push pipeline sends the same event to registered mobile devices.

alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check check (notification_type = any (array[
  'new_follower','profile_respect',
  'club_membership_request','club_membership_invite','club_membership_approved','club_membership_rejected','club_membership_cancelled','club_membership_left','club_membership_removed',
  'federation_registration_request','federation_registration_invite','federation_registration_approved','federation_registration_rejected','federation_registration_cancelled','federation_registration_left','federation_registration_removed',
  'followed_player_training','followed_player_match','followed_player_tournament_result','followed_entity_event','followed_entity_tournament',
  'ihs_welcome','followed_event_series_round_result','achievement_unlocked'
]::text[]));

create or replace function public.notify_achievement_unlocked()
returns trigger
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare
  d record;
  tier_label text;
begin
  select code,name,description,points,rarity into d
  from public.achievement_definitions
  where code=new.achievement_code;

  if not found then return new; end if;

  tier_label := case lower(coalesce(d.rarity,'bronze'))
    when 'silver' then 'Silver'
    when 'gold' then 'Gold'
    when 'platinum' then 'Platinum'
    else 'Bronze'
  end;

  insert into public.notifications(
    recipient_id,actor_id,notification_type,entity_type,entity_id,title,body,action_url
  ) values (
    new.user_id,null,'achievement_unlocked','achievement',null,
    'Achievement odomknutý: '||d.name,
    tier_label||' · +'||coalesce(d.points,0)::text||' B · '||coalesce(d.description,''),
    '/profil/achievements/?achievement='||d.code
  );
  return new;
end;
$$;

revoke all on function public.notify_achievement_unlocked() from public, anon, authenticated;

drop trigger if exists trg_notify_achievement_unlocked on public.player_achievements;
create trigger trg_notify_achievement_unlocked
after insert on public.player_achievements
for each row execute function public.notify_achievement_unlocked();
