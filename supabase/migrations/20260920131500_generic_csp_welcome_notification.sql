create or replace function public.init_ihs_for_profile()
returns trigger
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare
  v_action_url text;
begin
  if tg_op='INSERT' then
    v_action_url := case
      when new.role::text in ('club','organization','admin') or coalesce(new.is_admin,false)
        then '/profil-ul/'
      else '/profil/'
    end;

    if not exists (
      select 1 from public.notifications
      where recipient_id=new.id and notification_type='welcome'
    ) then
      insert into public.notifications(
        recipient_id,actor_id,notification_type,entity_type,entity_id,title,body,action_url
      ) values (
        new.id,null,'welcome','profile',new.id,
        'Vitaj v CSP',
        'Tvoj účet Connect Sports Pro je pripravený. Nastav si profil a začni používať funkcie svojho účtu.',
        v_action_url
      );
    end if;
  end if;

  if new.role::text <> 'player' then
    delete from public.notifications
    where recipient_id=new.id and notification_type='ihs_welcome';
    return new;
  end if;

  insert into public.player_ihs_profiles(player_id)
  values(new.id)
  on conflict(player_id) do nothing;

  return new;
end;
$function$;

delete from public.notifications n
using public.profiles p
where n.recipient_id=p.id
  and n.notification_type='ihs_welcome'
  and p.role::text <> 'player';

insert into public.notifications(
  recipient_id,actor_id,notification_type,entity_type,entity_id,title,body,action_url
)
select p.id,null,'welcome','profile',p.id,
       'Vitaj v CSP',
       'Tvoj účet Connect Sports Pro je pripravený. Nastav si profil a začni používať funkcie svojho účtu.',
       case when p.role::text in ('club','organization','admin') or p.is_admin then '/profil-ul/' else '/profil/' end
from public.profiles p
where lower(p.email)='managertest@csp.com'
  and not exists(
    select 1 from public.notifications n where n.recipient_id=p.id and n.notification_type='welcome'
  );