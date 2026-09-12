insert into public.score_action_definitions (
  sport_code, discipline_code, event_key, label, label_key,
  score_delta, metric_key, metric_value_mode, metric_value_default,
  value_min, value_max, button_style, sort_order, available_in, is_active
)
select
  'billiard', d.discipline_code, 'standard_minus', '−1', 'score.action.standard_minus',
  -1, null, 'fixed', 1,
  null, null, 'secondary', 11, array['tournament','training']::text[], true
from (values ('8-ball'),('9-ball'),('10-ball')) as d(discipline_code)
on conflict (sport_code, discipline_code, event_key)
do update set
  label=excluded.label,
  label_key=excluded.label_key,
  score_delta=excluded.score_delta,
  metric_key=excluded.metric_key,
  metric_value_mode=excluded.metric_value_mode,
  metric_value_default=excluded.metric_value_default,
  value_min=excluded.value_min,
  value_max=excluded.value_max,
  button_style=excluded.button_style,
  sort_order=excluded.sort_order,
  available_in=excluded.available_in,
  is_active=true,
  updated_at=now();

