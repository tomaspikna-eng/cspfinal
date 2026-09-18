-- Expose the stable snapshot in the session detail payload.
do $$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='get_my_training_session_detail' limit 1;

  if position('session_summary' in v_def)=0 then
    v_def:=replace(
      v_def,
      '''average_frame_seconds'',v_avg,',
      '''average_frame_seconds'',v_avg,''session_summary'',coalesce(v_ts.session_summary,''{}''::jsonb),'
    );
    execute v_def;
  end if;
end $$;