-- Clean billiards CTA catalogue for both training scoreboard and Scoreboard TE.
-- Common 8/9/10-ball events: +1, -1, break & run, runout.
-- 9-ball: + golden break, three-foul win, combo win.
-- 10-ball: + three-foul win.

-- Normalize common labels and keep standard scoring active.
update public.score_action_definitions
set is_active=true, updated_at=now()
where sport_code='billiard'
  and discipline_code in ('8-ball','9-ball','10-ball')
  and event_key in ('standard_point','standard_minus','break_and_run');

update public.score_action_definitions
set label='ČISTÁ HRA',
    label_key='score.action.break_and_run',
    metric_key='break_and_run',
    score_delta=1,
    metric_value_mode='fixed',
    metric_value_default=1,
    available_in=array['tournament','training']::text[],
    button_style='positive',
    sort_order=20,
    is_active=true,
    updated_at=now()
where sport_code='billiard'
  and discipline_code in ('8-ball','9-ball','10-ball')
  and event_key='break_and_run';

-- DOHRÁVKA = player clears the table but did not break.
insert into public.score_action_definitions(
  sport_code,discipline_code,event_key,label,label_key,score_delta,metric_key,
  metric_value_mode,metric_value_default,available_in,button_style,sort_order,is_active
)
select
  'billiard',d,'runout','DOHRÁVKA','score.action.runout',1,'runout',
  'fixed',1,array['tournament','training']::text[],'positive',25,true
from unnest(array['8-ball','9-ball','10-ball']::text[]) d
where not exists (
  select 1 from public.score_action_definitions x
  where x.sport_code='billiard' and x.discipline_code=d and x.event_key='runout'
);

update public.score_action_definitions
set label='DOHRÁVKA',
    label_key='score.action.runout',
    score_delta=1,
    metric_key='runout',
    metric_value_mode='fixed',
    metric_value_default=1,
    available_in=array['tournament','training']::text[],
    button_style='positive',
    sort_order=25,
    is_active=true,
    updated_at=now()
where sport_code='billiard'
  and discipline_code in ('8-ball','9-ball','10-ball')
  and event_key='runout';

-- 9-ball special actions.
update public.score_action_definitions
set label='ESO',score_delta=1,metric_key='golden_break',
    available_in=array['tournament','training']::text[],
    button_style='positive',sort_order=30,is_active=true,updated_at=now()
where sport_code='billiard' and discipline_code='9-ball' and event_key='golden_break';

update public.score_action_definitions
set label='KOMBO',score_delta=1,metric_key='combo_win',
    available_in=array['tournament','training']::text[],
    button_style='positive',sort_order=35,is_active=true,updated_at=now()
where sport_code='billiard' and discipline_code='9-ball' and event_key='combo_win';

update public.score_action_definitions
set label='3 CHYBY',score_delta=1,metric_key='three_foul_win',
    available_in=array['tournament','training']::text[],
    button_style='warning',sort_order=40,is_active=true,updated_at=now()
where sport_code='billiard' and discipline_code='9-ball' and event_key='three_foul_win';

-- 10-ball: only three-foul special rule beyond the common events.
update public.score_action_definitions
set label='3 CHYBY',score_delta=1,metric_key='three_foul_win',
    available_in=array['tournament','training']::text[],
    button_style='warning',sort_order=40,is_active=true,updated_at=now()
where sport_code='billiard' and discipline_code='10-ball' and event_key='three_foul_win';

-- Remove obsolete/sport-inappropriate CTAs.
update public.score_action_definitions
set is_active=false,updated_at=now()
where sport_code='billiard'
  and (
    (discipline_code='8-ball' and event_key='eight_on_break')
    or (discipline_code='10-ball' and event_key='golden_break')
    or (discipline_code='8-ball' and event_key in ('golden_break','combo_win','three_foul_win'))
    or (discipline_code='10-ball' and event_key='combo_win')
  );
