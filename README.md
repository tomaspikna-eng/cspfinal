# Connect Sports Pro — Scoreboards

Statický deploy balík s dvoma oddelenými edíciami scoreboardu.

## Cesty

- `/scoreboard/` — tréning a Live prevádzka klubu. Funguje aj anonymne a nečíta turnajové tokeny.
- `/scoreboard-te/` — Tournament Edition. Načíta turnajový zápas cez `match_id` + `match_token`, prípadne pevný tablet cez `device_token`.

## Smart výsledok v TE

Smart režim je predvolene zapnutý. Po dosiahnutí víťazného skóre TE automaticky zavolá RPC `complete_scoreboard_match`. Pri dočasnej chybe vykoná tri kontrolované pokusy a potom ponechá tlačidlo na ručné zopakovanie.

- Smart zapnutý: `/scoreboard-te/?match_id=...&match_token=...`
- Smart vypnutý: `/scoreboard-te/?match_id=...&match_token=...&smart=0`
- Pevné stanovisko: `/scoreboard-te/?device_token=...`

Balík je pripravený na statický deploy z koreňa repozitára. `assets/csp-auth.js` obsahuje verejnú konfiguráciu Supabase klienta; oprávnenia zápisu musia zostať chránené RLS/RPC na serveri.

## TE pripravenosť a time-out

Pred nasadením nových ovládačov aplikujte migráciu `supabase/migrations/0017_scoreboard_te_ready_timeout.sql`. Pripravenosť sa zapisuje do existujúcich polí `player1_ready_at` a `player2_ready_at`; po potvrdení oboch hráčov sa zápas prepne na `in_progress`. Time-out sa zapisuje do `player1_timeout_active` a `player2_timeout_active`, takže zoznam zápasov môže stav zobraziť ako živý badge.
