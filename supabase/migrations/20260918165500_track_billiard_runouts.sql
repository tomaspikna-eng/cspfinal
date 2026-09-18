-- Track DOHRÁVKA separately in training performance summaries.
do $$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='refresh_my_training_session_summary' limit 1;

  if position('v_runouts integer' in v_def)=0 then
    v_def:=replace(v_def,
      'v_break_and_runs integer := 0;',
      'v_break_and_runs integer := 0; v_runouts integer := 0;'
    );

    v_def:=replace(v_def,
      'count(*) filter(where se.event_key=''break_and_run'' and se.undone_at is null)::integer,',
      'count(*) filter(where se.event_key=''break_and_run'' and se.undone_at is null)::integer, count(*) filter(where se.event_key=''runout'' and se.undone_at is null)::integer,'
    );

    v_def:=replace(v_def,
      'into v_positive_events,v_break_and_runs,v_golden_breaks,v_combo_wins,v_three_foul_wins',
      'into v_positive_events,v_break_and_runs,v_runouts,v_golden_breaks,v_combo_wins,v_three_foul_wins'
    );

    v_def:=replace(v_def,
      '''break_and_runs'',v_break_and_runs,',
      '''break_and_runs'',v_break_and_runs,''runouts'',v_runouts,'
    );

    execute v_def;
  end if;
end $$;

update public.training_sessions ts
set session_summary = coalesce(ts.session_summary,'{}'::jsonb)
  || jsonb_build_object(
      'runouts',
      coalesce((
        select count(*)::integer
        from public.score_events se
        where se.training_session_id=ts.id
          and se.event_key='runout'
          and se.undone_at is null
      ),0)
    )
where ts.status='completed';