# CSP 2.0 – Double KO engine fix

## Opravený problém

Pôvodný DKO model nebol štandardný Double Elimination. Po Winner vetve spájal hráčov do dvoch semifinále a samostatného zápasu o 3. miesto. To porušovalo pravidlo, že hráč vypadáva až po druhej prehre, a routing Loser vetvy nebol generický.

## Nový model

- generický pavúk pre 4, 8, 16 a 32 slotov,
- automatické BYE/VO,
- Winner Bracket s `log2(N)` kolami,
- Loser Bracket s `2 × (log2(N) − 1)` kolami,
- Losers Final,
- Grand Final GF1,
- automatický reset GF2, ak víťaz Loser vetvy vyhrá GF1,
- hráč je vyradený až po druhej prehre,
- BYE sa nikdy neposiela ako fiktívny porazený do Loser vetvy,
- starý uložený DKO stav sa automaticky zahodí a prebuduje cez `schemaVersion: 2`.

## Testy

Automatické simulačné testy prešli pre:

- 4 hráčov bez resetu: 6 zápasov,
- 4 hráčov s resetom: 7 zápasov,
- 8 hráčov bez resetu: 14 zápasov,
- 8 hráčov s resetom: 15 zápasov,
- 16 hráčov bez resetu: 30 zápasov,
- 16 hráčov s resetom: 31 zápasov,
- 32 hráčov bez resetu: 62 zápasov,
- 32 hráčov s resetom: 63 zápasov.

BYE scenáre prešli pre 5, 6, 7, 9, 12 a 15 hráčov.

Pri každom teste bolo overené:

- existuje presne jeden víťaz,
- žiadny hráč nemá viac ako dve prehry,
- všetci okrem víťaza majú dve prehry,
- GF2 sa otvorí iba po víťazstve Loser-bracket šampióna v GF1,
- BYE objekt sa nedostane do Loser vetvy.

## Otvorená integračná úloha

Frontendový engine je opravený. Databázové polia `next_match_id` a `loser_next_match_id` už existujú, ale aktuálny frontend stále ukladá zápasy primárne cez `round_key`. Ďalší krok je pri vytvorení DKO turnaja persistovať kompletnú routing mapu do Supabase, aby bol celý pavúk nezávislý od localStorage.
