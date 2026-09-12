create or replace function public.create_tournament_scorer(p_tournament_id uuid, p_name text)
returns public.tournament_scorers
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare v public.tournament_scorers;
begin
  if nullif(trim(p_name),'') is null then raise exception 'Scorer name is required'; end if;
  if not exists(select 1 from public.tournaments t where t.id=p_tournament_id and (t.owner_id=auth.uid() or public.is_admin(auth.uid()))) then
    raise exception 'Tournament not found or access denied';
  end if;
  insert into public.tournament_scorers(tournament_id,name,created_by)
  values(p_tournament_id,trim(p_name),auth.uid()) returning * into v;
  return v;
end $$;

create or replace function public.get_tournament_scorer_matches(p_scorer_token uuid)
returns table(
  scorer_name text,
  tournament_id uuid,
  tournament_name text,
  match_id uuid,
  round_key text,
  round_number integer,
  match_number integer,
  resource_label text,
  player1_id uuid,
  player1_name text,
  player2_id uuid,
  player2_name text,
  score1 integer,
  score2 integer,
  match_status text
)
language sql
stable
security definer
set search_path to 'public','pg_temp'
as $$
  select s.name,t.id,t.name,m.id,m.round_key,m.round_number,m.match_number,m.tournament_resource_label,
         m.player1_id,p1.name,m.player2_id,p2.name,coalesce(m.score1,0),coalesce(m.score2,0),m.status
  from public.tournament_scorers s
  join public.tournaments t on t.id=s.tournament_id
  join public.matches m on m.tournament_id=t.id
  left join public.tournament_players p1 on p1.id=m.player1_id
  left join public.tournament_players p2 on p2.id=m.player2_id
  where s.access_token=p_scorer_token and s.is_active=true
    and m.player1_id is not null and m.player2_id is not null
    and m.status not in ('completed','forfeited','cancelled')
  order by case when m.status in ('in_progress','live') then 0 when m.tournament_resource_id is not null then 1 else 2 end,
           coalesce(m.round_number,999999),coalesce(m.match_number,999999),m.created_at;
$$;

grant execute on function public.create_tournament_scorer(uuid,text) to authenticated;
grant execute on function public.get_tournament_scorer_matches(uuid) to anon, authenticated;

