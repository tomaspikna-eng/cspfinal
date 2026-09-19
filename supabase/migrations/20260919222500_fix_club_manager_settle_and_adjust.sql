drop function if exists public.club_manager_settle_session(uuid);

create or replace function public.club_manager_adjust_session(
  p_session_id uuid,
  p_accumulated_seconds integer default null,
  p_adjustment_amount numeric default null,
  p_adjustment_note text default null
)
returns public.club_manager_live_sessions
language plpgsql security definer set search_path='public','pg_temp'
as $$
declare
  v public.club_manager_live_sessions;
  v_seconds integer;
  v_base numeric(10,2);
begin
  select ls.* into v
  from public.club_manager_live_sessions ls
  join public.clubs c on c.id=ls.club_id
  where ls.id=p_session_id
    and (c.owner_id=auth.uid() or public.is_admin(auth.uid()))
    and public.has_club_manager_access(auth.uid())
  for update of ls;

  if v.id is null then raise exception 'SESSION_NOT_FOUND'; end if;
  if v.status not in ('running','paused','stopped') then raise exception 'SESSION_NOT_ADJUSTABLE'; end if;

  v_seconds := coalesce(
    p_accumulated_seconds,
    v.accumulated_seconds + case
      when v.status='running' then greatest(0,floor(extract(epoch from (now()-v.started_at)))::integer)
      else 0
    end
  );
  if v_seconds < 0 then raise exception 'INVALID_TIME'; end if;

  v_base := round(((v_seconds::numeric/3600) * v.hourly_rate * v.rate_multiplier)::numeric,2);

  update public.club_manager_live_sessions
  set accumulated_seconds=v_seconds,
      started_at=case when v.status='running' then now() else started_at end,
      adjustment_amount=coalesce(p_adjustment_amount,adjustment_amount),
      adjustment_note=nullif(trim(coalesce(p_adjustment_note,adjustment_note)),''),
      total_amount=v_base,
      final_amount=greatest(0,v_base+coalesce(p_adjustment_amount,adjustment_amount,0)),
      updated_at=now()
  where id=v.id
  returning * into v;

  return v;
end $$;

grant execute on function public.club_manager_adjust_session(uuid,integer,numeric,text) to authenticated;
grant execute on function public.club_manager_settle_session(uuid,text,numeric) to authenticated;
