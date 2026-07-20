# CSP 2.0 – Multi-phase transition fix

## Opravený problém
Po dohraní skupín frontend vytvoril `phase2` iba v localStorage. Databázová RR fáza zostala aktívna, `current_phase_id` sa nezmenilo a na inom zariadení alebo po strate lokálneho stavu neexistoval spoľahlivý prechod do SKO/DKO.

## Nové správanie
1. Každý skupinový výsledok sa ukladá s `phase_id` skupinovej fázy.
2. Po poslednom skupinovom výsledku sa vypočítajú postupujúci a krížové nasadenie.
3. Frontend zavolá RPC `complete_round_robin_phase`.
4. RPC uloží `phase_qualifiers`, uzavrie RR fázu, vytvorí aktívnu SKO/DKO fázu a aktualizuje `tournaments.current_phase_id`.
5. Frontend vygeneruje cieľový pavúk, prekreslí turnaj a automaticky posunie obrazovku na druhú fázu.
6. Pri reloadovaní sa načítajú `tournament_phases`; ak druhá fáza už existuje, nevytvorí sa duplicitne.
7. Zápasy druhej fázy sa ukladajú s jej `phase_id`, `round_number`, `match_number` a `bracket_side`.

## Podporované prechody
- Round Robin → Single KO
- Round Robin → Double KO
- Round Robin → chránené nasadenie Single KO

## Ochrany
- žiadne duplicitné vytvorenie druhej fázy,
- prechod sa spustí iba po kompletnom dohraní všetkých skupín,
- presná databázová chyba sa zobrazí organizátorovi,
- existujúci Single KO a Double KO engine zostal zachovaný.
