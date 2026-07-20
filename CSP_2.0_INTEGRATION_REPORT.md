# CSP 2.0 integration report

Integrated Supabase migrations 20260720080646–20260720081834 and connected the current frontend to tournament lifecycle, training lifecycle fields, profile tournament history and profile statistics.

## Integrated
- database migrations tracked in repository
- profile tournament history via `user_tournament_history`
- profile statistics via `user_sport_statistics`
- tournament complete/archive RPC buttons
- initial `tournament_phases` row on tournament creation
- completed training lifecycle fields when saving scoreboard results

## Still requires dedicated engine work
The current frontend Double KO generator explicitly states that Losers Bracket routing is unfinished. The database now supports `next_match_id` and `loser_next_match_id`, but the frontend must generate the complete routing map for 4/8/16/32-player DKO brackets and persist those links. Round Robin → KO must also generate phase-2 matches and qualifier payloads before calling `complete_round_robin_phase`.

## Supabase dashboard setting
Enable Auth → Password Security → Leaked Password Protection manually.
