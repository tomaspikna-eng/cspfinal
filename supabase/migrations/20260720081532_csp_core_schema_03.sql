-- CSP 2.0 core schema
alter table public.tournaments drop constraint if exists tournaments_status_check;
alter table public.tournaments add constraint tournaments_status_check check (status in ('draft','active','completed','archived'));
alter table public.tournaments add column if not exists started_at timestamptz;
alter table public.tournaments add column if not exists completed_at timestamptz;
alter table public.tournaments add column if not exists archived_at timestamptz;
alter table public.tournaments add column if not exists current_phase_id uuid;
alter table public.tournaments add column if not exists config jsonb not null default '{}'::jsonb;

alter table public.training_sessions add column if not exists status text not null default 'completed';
alter table public.training_sessions add column if not exists started_at timestamptz;
alter table public.training_sessions add column if not exists paused_at timestamptz;
alter table public.training_sessions add column if not exists completed_at timestamptz;
alter table public.training_sessions add column if not exists elapsed_seconds integer not null default 0;
alter table public.training_sessions add column if not exists archived_at timestamptz;
alter table public.training_sessions add column if not exists updated_at timestamptz not null default now();
alter table public.training_sessions drop constraint if exists training_sessions_status_check;
alter table public.training_sessions add constraint training_sessions_status_check check(status in ('draft','active','paused','completed','archived'));
alter table public.training_sessions drop constraint if exists training_sessions_elapsed_nonnegative;
alter table public.training_sessions add constraint training_sessions_elapsed_nonnegative check(elapsed_seconds >= 0 and coalesce(duration_seconds,0) >= 0);

create table if not exists public.tournament_phases(
 id uuid primary key default gen_random_uuid(), tournament_id uuid not null references public.tournaments(id) on delete cascade,
 phase_number integer not null, phase_type text not null check(phase_type in ('rr','sko','dko','karty','placement')),
 status text not null default 'draft' check(status in ('draft','active','completed','archived')),
 config jsonb not null default '{}'::jsonb, started_at timestamptz, completed_at timestamptz,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(tournament_id,phase_number)
);
create index if not exists tournament_phases_tournament_id_idx on public.tournament_phases(tournament_id);
alter table public.tournaments drop constraint if exists tournaments_current_phase_id_fkey;
alter table public.tournaments add constraint tournaments_current_phase_id_fkey foreign key(current_phase_id) references public.tournament_phases(id) on delete set null;

create table if not exists public.phase_qualifiers(
 id uuid primary key default gen_random_uuid(), phase_id uuid not null references public.tournament_phases(id) on delete cascade,
 tournament_player_id uuid not null references public.tournament_players(id) on delete cascade,
 source_group integer, source_position integer, seed integer not null, created_at timestamptz not null default now(),
 unique(phase_id,tournament_player_id), unique(phase_id,seed)
);

create table if not exists public.tournament_results(
 id uuid primary key default gen_random_uuid(), tournament_id uuid not null references public.tournaments(id) on delete cascade,
 tournament_player_id uuid not null references public.tournament_players(id) on delete cascade,
 user_id uuid references public.profiles(id) on delete set null, final_position integer,
 matches_played integer not null default 0, wins integer not null default 0, losses integer not null default 0,
 score_for integer not null default 0, score_against integer not null default 0, created_at timestamptz not null default now(),
 unique(tournament_id,tournament_player_id)
);
create index if not exists tournament_results_user_id_idx on public.tournament_results(user_id);
create index if not exists tournament_results_tournament_id_idx on public.tournament_results(tournament_id);

create table if not exists public.tournament_fee_categories(
 id uuid primary key default gen_random_uuid(), tournament_id uuid not null references public.tournaments(id) on delete cascade,
 name text not null, amount numeric(12,2) not null check(amount>=0), currency text not null default 'EUR',
 eligibility_rule jsonb not null default '{}'::jsonb, is_active boolean not null default true,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(tournament_id,name)
);
create table if not exists public.tournament_player_payments(
 id uuid primary key default gen_random_uuid(), tournament_player_id uuid not null unique references public.tournament_players(id) on delete cascade,
 fee_category_id uuid references public.tournament_fee_categories(id) on delete set null,
 entry_fee_amount numeric(12,2) not null default 0 check(entry_fee_amount>=0), currency text not null default 'EUR',
 payment_status text not null default 'unpaid' check(payment_status in ('unpaid','paid','waived','pending_confirmation','refunded')),
 payment_method text, paid_at timestamptz, manual_discount_reason text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.audit_logs(
 id bigint generated always as identity primary key, user_id uuid references public.profiles(id) on delete set null,
 entity_type text not null, entity_id uuid, action text not null, metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
create index if not exists audit_logs_entity_idx on public.audit_logs(entity_type,entity_id,created_at desc);

alter table public.matches add column if not exists phase_id uuid references public.tournament_phases(id) on delete cascade;
alter table public.matches add column if not exists round_number integer;
alter table public.matches add column if not exists match_number integer;
alter table public.matches add column if not exists bracket_side text check(bracket_side in ('rr','winners','losers','grand_final','reset','placement'));
alter table public.matches add column if not exists next_match_id uuid references public.matches(id) on delete set null;
alter table public.matches add column if not exists loser_next_match_id uuid references public.matches(id) on delete set null;
alter table public.matches add column if not exists player1_source text;
alter table public.matches add column if not exists player2_source text;
alter table public.matches add column if not exists station_id uuid references public.stations(id) on delete set null;
alter table public.matches add column if not exists scheduled_at timestamptz;
alter table public.matches add column if not exists started_at timestamptz;
alter table public.matches add column if not exists completed_at timestamptz;
alter table public.matches add column if not exists called_at timestamptz;
alter table public.matches add column if not exists arrival_deadline_at timestamptz;
alter table public.matches add column if not exists penalty_1_at timestamptz;
alter table public.matches add column if not exists penalty_2_at timestamptz;
alter table public.matches add column if not exists penalty_3_at timestamptz;
alter table public.matches add column if not exists forfeit_at timestamptz;
alter table public.matches add column if not exists late_player_id uuid references public.tournament_players(id) on delete set null;
alter table public.matches add column if not exists penalty_score_awarded integer not null default 0;
alter table public.matches add column if not exists forfeit_reason text;
alter table public.matches add column if not exists match_call_status text not null default 'not_called';
alter table public.matches add column if not exists player1_ready_at timestamptz;
alter table public.matches add column if not exists player2_ready_at timestamptz;
alter table public.matches add column if not exists shot_clock_enabled boolean not null default false;
alter table public.matches add column if not exists shot_clock_seconds integer not null default 30;
alter table public.matches add column if not exists post_break_seconds integer not null default 60;
alter table public.matches add column if not exists extension_seconds integer not null default 30;
alter table public.matches add column if not exists extensions_allowed integer not null default 1;
alter table public.matches add column if not exists extensions_used_player1 integer not null default 0;
alter table public.matches add column if not exists extensions_used_player2 integer not null default 0;
alter table public.matches add column if not exists shot_clock_operator_id uuid references public.profiles(id) on delete set null;
alter table public.matches add column if not exists shot_clock_current_player_id uuid references public.tournament_players(id) on delete set null;
alter table public.matches add column if not exists shot_clock_started_at timestamptz;
alter table public.matches add column if not exists shot_clock_remaining_seconds integer;
alter table public.matches add column if not exists shot_clock_paused boolean not null default true;
alter table public.matches drop constraint if exists matches_status_check;
alter table public.matches add constraint matches_status_check check(status in ('pending','waiting_for_table','ready','called','player_arriving','live','in_progress','completed','forfeited','disputed'));
create index if not exists matches_phase_id_idx on public.matches(phase_id);
create index if not exists matches_next_match_id_idx on public.matches(next_match_id);
create index if not exists matches_loser_next_match_id_idx on public.matches(loser_next_match_id);
create index if not exists matches_station_id_idx on public.matches(station_id);

alter table public.articles drop constraint if exists articles_status_check;
alter table public.articles add constraint articles_status_check check(status in ('draft','published','archived'));

alter table public.tournament_phases enable row level security;
alter table public.phase_qualifiers enable row level security;
alter table public.tournament_results enable row level security;
alter table public.tournament_fee_categories enable row level security;
alter table public.tournament_player_payments enable row level security;
alter table public.audit_logs enable row level security;

create policy tournament_phases_owner_all on public.tournament_phases for all to authenticated using(exists(select 1 from public.tournaments t where t.id=tournament_id and t.owner_id=(select auth.uid()))) with check(exists(select 1 from public.tournaments t where t.id=tournament_id and t.owner_id=(select auth.uid())));
create policy tournament_phases_select on public.tournament_phases for select to anon,authenticated using(exists(select 1 from public.tournaments t where t.id=tournament_id and t.status<>'draft'));
create policy phase_qualifiers_owner_all on public.phase_qualifiers for all to authenticated using(exists(select 1 from public.tournament_phases p join public.tournaments t on t.id=p.tournament_id where p.id=phase_id and t.owner_id=(select auth.uid()))) with check(exists(select 1 from public.tournament_phases p join public.tournaments t on t.id=p.tournament_id where p.id=phase_id and t.owner_id=(select auth.uid())));
create policy phase_qualifiers_select on public.phase_qualifiers for select to anon,authenticated using(exists(select 1 from public.tournament_phases p join public.tournaments t on t.id=p.tournament_id where p.id=phase_id and t.status<>'draft'));
create policy tournament_results_owner_all on public.tournament_results for all to authenticated using(exists(select 1 from public.tournaments t where t.id=tournament_id and t.owner_id=(select auth.uid()))) with check(exists(select 1 from public.tournaments t where t.id=tournament_id and t.owner_id=(select auth.uid())));
create policy tournament_results_select on public.tournament_results for select to anon,authenticated using(exists(select 1 from public.tournaments t where t.id=tournament_id and t.status in ('completed','archived')));
create policy fee_categories_owner_all on public.tournament_fee_categories for all to authenticated using(exists(select 1 from public.tournaments t where t.id=tournament_id and t.owner_id=(select auth.uid()))) with check(exists(select 1 from public.tournaments t where t.id=tournament_id and t.owner_id=(select auth.uid())));
create policy payments_owner_all on public.tournament_player_payments for all to authenticated using(exists(select 1 from public.tournament_players tp join public.tournaments t on t.id=tp.tournament_id where tp.id=tournament_player_id and t.owner_id=(select auth.uid()))) with check(exists(select 1 from public.tournament_players tp join public.tournaments t on t.id=tp.tournament_id where tp.id=tournament_player_id and t.owner_id=(select auth.uid())));
create policy audit_logs_select_admin on public.audit_logs for select to authenticated using(public.is_admin((select auth.uid())));

create policy training_sessions_update_owner on public.training_sessions for update to authenticated using(owner_id=(select auth.uid())) with check(owner_id=(select auth.uid()));
