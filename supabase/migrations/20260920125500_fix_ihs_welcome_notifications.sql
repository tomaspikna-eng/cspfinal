create or replace function public.init_ihs_for_profile()
returns trigger
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_created uuid;
  v_notification_id uuid;
begin
  if new.role::text <> 'player' then
    delete from public.notifications
    where recipient_id = new.id
      and notification_type = 'ihs_welcome';
    return new;
  end if;

  insert into public.player_ihs_profiles(player_id)
  values(new.id)
  on conflict(player_id) do nothing
  returning player_id into v_created;

  if v_created is not null and new.email is not null then
    insert into public.notifications(
      recipient_id, actor_id, notification_type, entity_type, entity_id,
      title, body, action_url
    ) values (
      new.id, null, 'ihs_welcome', 'ihs_profile', new.id,
      'CSP IHS je aktívny',
      'Od registrácie sa ti automaticky počíta CSP Rating a Level z VERIFIED turnajových výsledkov.',
      '/profil/'
    ) returning id into v_notification_id;

    insert into public.notification_email_outbox(
      notification_id, recipient_id, recipient_email, template_key, payload
    ) values (
      v_notification_id,
      new.id,
      new.email,
      'ihs_welcome',
      jsonb_build_object(
        'title','CSP International Handicap System',
        'body','CSP IHS je aktívny od tvojej registrácie. Rating a Level sa menia automaticky podľa VERIFIED turnajových výsledkov. Hodnoty nie je možné ručne upravovať.',
        'action_url','/profil/',
        'entity_type','ihs_profile',
        'entity_id',new.id
      )
    );

    update public.player_ihs_profiles
      set explanation_queued_at = now(), updated_at = now()
      where player_id = new.id;
  end if;

  return new;
end;
$function$;

delete from public.notifications n
using public.profiles p
where n.recipient_id=p.id
  and n.notification_type='ihs_welcome'
  and p.role::text <> 'player';