alter table public.tournaments add column if not exists started_at timestamptz, add column if not exists completed_at timestamptz, add column if not exists archived_at timestamptz, add column if not exists current_phase_id uuid, add column if not exists config jsonb not null default '{}'::jsonb;
alter table public.tournaments drop constraint if exists tournaments_status_check;
alter table public.tournaments add constraint tournaments_status_check check (status in ('draft','active','completed','archived'));

alter table public.training_sessions add column if not exists status text not null default 'completed', add column if not exists started_at timestamptz, add column if not exists paused_at timestamptz, add column if not exists completed_at timestamptz, add column if not exists elapsed_seconds integer not null default 0, add column if not exists archived_at timestamptz, add column if not exists updated_at timestamptz not null default now();
update public.training_sessions set started_at=coalesce(started_at,played_at), completed_at=coalesce(completed_at,played_at), elapsed_seconds=greatest(coalesce(elapsed_seconds,duration_seconds,0),0) where status='completed';
alter table public.training_sessions drop constraint if exists training_sessions_status_check;
alter table public.training_sessions add constraint training_sessions_status_check check (status in ('draft','active','paused','completed','archived'));
alter table public.training_sessions drop constraint if exists training_sessions_elapsed_nonnegative;
alter table public.training_sessions add constraint training_sessions_elapsed_nonnegative check (elapsed_seconds>=0 and (duration_seconds is null or duration_seconds>=0));

alter table public.articles drop constraint if exists articles_status_check;
alter table public.articles add constraint articles_status_check check (status in ('draft','published','archived'));

create table if not exists public.tournament_phases (
 id uuid primary key default gen_random_uuid(), tournament_id uuid not null references public.tournaments(id) on delete cascade,
 phase_number integer not null, phase_type text not null, status text not null default 'draft', config jsonb not null default '{}'::jsonb,
 started_at timestamptz, completed_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(tournament_id,phase_number), check(phase_number>0),
 check(phase_type in ('round_robin','single_elimination','double_elimination','cards','placement')),
 check(status in ('draft','active','completed','archived'))
);

do $$ begin if not exists(select 1 from pg_constraint where conname='tournaments_current_phase_id_fkey') then alter table public.tournaments add constraint tournaments_current_phase_id_fkey foreign key(current_phase_id) references public.tournament_phases(id) on delete set null; end if; end $$;

alter table public.matches add column if not exists phase_id uuid, add column if not exists round_number integer, add column if not exists match_number integer, add column if not exists bracket_side text, add column if not exists next_match_id uuid, add column if not exists loser_next_match_id uuid, add column if not exists player1_source text, add column if not exists player2_source text, add column if not exists station_id uuid, add column if not exists scheduled_at timestamptz, add column if not exists called_at timestamptz, add column if not exists arrival_deadline_at timestamptz, add column if not exists penalty_1_at timestamptz, add column if not exists penalty_2_at timestamptz, add column if not exists penalty_3_at timestamptz, add column if not exists forfeit_at timestamptz, add column if not exists late_player_id uuid, add column if not exists penalty_score_awarded integer not null default 0, add column if not exists forfeit_reason text, add column if not exists match_call_status text not null default 'not_called', add column if not exists player1_ready_at timestamptz, add column if not exists player2_ready_at timestamptz, add column if not exists started_at timestamptz, add column if not exists completed_at timestamptz, add column if not exists shot_clock_enabled boolean not null default false, add column if not exists shot_clock_seconds integer not null default 30, add column if not exists post_break_seconds integer not null default 60, add column if not exists extension_seconds integer not null default 30, add column if not exists extensions_allowed integer not null default 1, add column if not exists extensions_used_player1 integer not null default 0, add column if not exists extensions_used_player2 integer not null default 0, add column if not exists shot_clock_operator_id uuid;
alter table public.matches drop constraint if exists matches_status_check;
alter table public.matches add constraint matches_status_check check(status in ('pending','waiting_for_table','ready','called','player_arriving','live','in_progress','completed','forfeited','disputed'));
alter table public.matches add constraint matches_bracket_side_check check(bracket_side is null or bracket_side in ('group','single','winners','losers','grand_final','placement'));
alter table public.matches add constraint matches_call_status_check check(match_call_status in ('not_called','called','arrival_window','penalty_1','penalty_2','penalty_3','forfeit_available','closed'));
alter table public.matches add constraint matches_ops_values_check check(penalty_score_awarded>=0 and shot_clock_seconds>0 and post_break_seconds>0 and extension_seconds>0 and extensions_allowed>=0 and extensions_used_player1>=0 and extensions_used_player2>=0);

do $$ begin
 if not exists(select 1 from pg_constraint where conname='matches_phase_id_fkey') then alter table public.matches add constraint matches_phase_id_fkey foreign key(phase_id) references public.tournament_phases(id) on delete set null; end if;
 if not exists(select 1 from pg_constraint where conname='matches_next_match_id_fkey') then alter table public.matches add constraint matches_next_match_id_fkey foreign key(next_match_id) references public.matches(id) on delete set null; end if;
 if not exists(select 1 from pg_constraint where conname='matches_loser_next_match_id_fkey') then alter table public.matches add constraint matches_loser_next_match_id_fkey foreign key(loser_next_match_id) references public.matches(id) on delete set null; end if;
 if not exists(select 1 from pg_constraint where conname='matches_late_player_id_fkey') then alter table public.matches add constraint matches_late_player_id_fkey foreign key(late_player_id) references public.tournament_players(id) on delete set null; end if;
 if not exists(select 1 from pg_constraint where conname='matches_station_id_fkey') then alter table public.matches add constraint matches_station_id_fkey foreign key(station_id) references public.stations(id) on delete set null; end if;
 if not exists(select 1 from pg_constraint where conname='matches_shot_clock_operator_id_fkey') then alter table public.matches add constraint matches_shot_clock_operator_id_fkey foreign key(shot_clock_operator_id) references public.profiles(id) on delete set null; end if;
end $$;

create table if not exists public.tournament_results (
 id uuid primary key default gen_random_uuid(), tournament_id uuid not null references public.tournaments(id) on delete cascade,
 tournament_player_id uuid not null references public.tournament_players(id) on delete cascade, user_id uuid references public.profiles(id) on delete set null,
 final_position integer, matches_played integer not null default 0, wins integer not null default 0, losses integer not null default 0,
 score_for integer not null default 0, score_against integer not null default 0, metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(tournament_id,tournament_player_id),
 check(final_position is null or final_position>0), check(matches_played>=0 and wins>=0 and losses>=0 and score_for>=0 and score_against>=0)
);
create table if not exists public.tournament_fee_categories (
 id uuid primary key default gen_random_uuid(), tournament_id uuid not null references public.tournaments(id) on delete cascade,
 name text not null, amount numeric(12,2) not null default 0, currency text not null default 'EUR', eligibility_rule jsonb not null default '{}'::jsonb,
 is_active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(tournament_id,name), check(amount>=0), check(char_length(currency)=3)
);
create table if not exists public.tournament_player_payments (
 id uuid primary key default gen_random_uuid(), tournament_id uuid not null references public.tournaments(id) on delete cascade,
 tournament_player_id uuid not null references public.tournament_players(id) on delete cascade, fee_category_id uuid references public.tournament_fee_categories(id) on delete set null,
 entry_fee_amount numeric(12,2) not null default 0, currency text not null default 'EUR', payment_status text not null default 'unpaid', payment_method text,
 paid_at timestamptz, manual_discount_reason text, metadata jsonb not null default '{}'::jsonb, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(tournament_id,tournament_player_id), check(entry_fee_amount>=0), check(char_length(currency)=3), check(payment_status in ('unpaid','paid','waived','pending_confirmation','refunded'))
);
create table if not exists public.audit_logs (
 id bigint generated always as identity primary key, user_id uuid references public.profiles(id) on delete set null,
 entity_type text not null, entity_id uuid, action text not null, metadata jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);

create index if not exists tournaments_owner_status_idx on public.tournaments(owner_id,status,created_at desc);
create index if not exists training_sessions_owner_status_idx on public.training_sessions(owner_id,status,played_at desc);
create index if not exists matches_tournament_status_idx on public.matches(tournament_id,status);
create index if not exists matches_phase_idx on public.matches(phase_id,round_number,match_number);
create index if not exists matches_station_status_idx on public.matches(station_id,status) where station_id is not null;
create index if not exists matches_next_match_idx on public.matches(next_match_id) where next_match_id is not null;
create index if not exists matches_loser_next_match_idx on public.matches(loser_next_match_id) where loser_next_match_id is not null;
create index if not exists tournament_results_user_idx on public.tournament_results(user_id,created_at desc) where user_id is not null;
create index if not exists tournament_results_position_idx on public.tournament_results(tournament_id,final_position);
create index if not exists tournament_payments_status_idx on public.tournament_player_payments(tournament_id,payment_status);
create index if not exists audit_logs_entity_idx on public.audit_logs(entity_type,entity_id,created_at desc);

create trigger tournament_phases_set_updated_at before update on public.tournament_phases for each row execute function public.set_updated_at();
create trigger tournament_results_set_updated_at before update on public.tournament_results for each row execute function public.set_updated_at();
create trigger tournament_fee_categories_set_updated_at before update on public.tournament_fee_categories for each row execute function public.set_updated_at();
create trigger tournament_player_payments_set_updated_at before update on public.tournament_player_payments for each row execute function public.set_updated_at();
create trigger training_sessions_set_updated_at before update on public.training_sessions for each row execute function public.set_updated_at();

alter table public.tournament_phases enable row level security;
alter table public.tournament_results enable row level security;
alter table public.tournament_fee_categories enable row level security;
alter table public.tournament_player_payments enable row level security;
alter table public.audit_logs enable row level security;

create policy tournament_phases_select on public.tournament_phases for select to anon,authenticated using(exists(select 1 from public.tournaments t where t.id=tournament_id and (t.owner_id=(select auth.uid()) or t.status<>'draft')));
create policy tournament_phases_owner_write on public.tournament_phases for all to authenticated using(exists(select 1 from public.tournaments t where t.id=tournament_id and t.owner_id=(select auth.uid()))) with check(exists(select 1 from public.tournaments t where t.id=tournament_id and t.owner_id=(select auth.uid())));
create policy tournament_results_select on public.tournament_results for select to anon,authenticated using(exists(select 1 from public.tournaments t where t.id=tournament_id and (t.owner_id=(select auth.uid()) or t.status in ('completed','archived'))));
create policy tournament_results_owner_write on public.tournament_results for all to authenticated using(exists(select 1 from public.tournaments t where t.id=tournament_id and t.owner_id=(select auth.uid()))) with check(exists(select 1 from public.tournaments t where t.id=tournament_id and t.owner_id=(select auth.uid())));
create policy tournament_fee_categories_select on public.tournament_fee_categories for select to anon,authenticated using(exists(select 1 from public.tournaments t where t.id=tournament_id and (t.owner_id=(select auth.uid()) or t.status<>'draft')));
create policy tournament_fee_categories_owner_write on public.tournament_fee_categories for all to authenticated using(exists(select 1 from public.tournaments t where t.id=tournament_id and t.owner_id=(select auth.uid()))) with check(exists(select 1 from public.tournaments t where t.id=tournament_id and t.owner_id=(select auth.uid())));
create policy tournament_player_payments_owner_all on public.tournament_player_payments for all to authenticated using(exists(select 1 from public.tournaments t where t.id=tournament_id and t.owner_id=(select auth.uid()))) with check(exists(select 1 from public.tournaments t where t.id=tournament_id and t.owner_id=(select auth.uid())));
create policy tournament_player_payments_player_select on public.tournament_player_payments for select to authenticated using(exists(select 1 from public.tournament_players tp where tp.id=tournament_player_id and tp.user_id=(select auth.uid())));
create policy audit_logs_admin_select on public.audit_logs for select to authenticated using(public.is_admin((select auth.uid())));
create policy audit_logs_own_select on public.audit_logs for select to authenticated using(user_id=(select auth.uid()));

drop policy if exists training_sessions_update_owner on public.training_sessions;
create policy training_sessions_update_owner on public.training_sessions for update to authenticated using(owner_id=(select auth.uid())) with check(owner_id=(select auth.uid()));

