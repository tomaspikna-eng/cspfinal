create or replace function public.auto_start_match_when_both_ready()
returns trigger
language plpgsql
as $$
begin
  if new.player1_ready_at is not null
     and new.player2_ready_at is not null
     and coalesce(new.status,'') not in ('in_progress','live','completed','forfeited','cancelled') then
    new.status := 'in_progress';
    new.started_at := coalesce(new.started_at, now());
    new.match_clock_started_at := coalesce(new.match_clock_started_at, now());
    new.match_call_status := 'playing';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_auto_start_match_when_both_ready on public.matches;
create trigger trg_auto_start_match_when_both_ready
before update on public.matches
for each row
execute function public.auto_start_match_when_both_ready();
