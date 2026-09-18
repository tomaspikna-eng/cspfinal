-- Technical/abandoned training sessions are not completed activities.
do $$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='get_my_player_profile_dashboard' limit 1;
  v_def := replace(v_def, 'ts.status in (''completed'',''archived'')', 'ts.status = ''completed''');
  execute v_def;

  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='profile_private' and p.proname='get_public_pro_plus_profile_core' limit 1;
  v_def := replace(v_def, 'ts.status in (''completed'',''archived'')', 'ts.status = ''completed''');
  execute v_def;
end $$;