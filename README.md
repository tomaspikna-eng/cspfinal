# Connect Sports Pro — Frontend (deploy balík)

Statický frontend CSP ekosystému. Čistý HTML/CSS/JS, žiadny build.
Priečinková štruktúra (`priečinok/index.html`) + `cleanUrls` vo Verceli.

## Nasadenie (Vercel)
1. Nahraj obsah tohto priečinka do ROOTA GitHub repa.
2. Vercel: Import repo → Framework Preset: **Other** → Build Command: *prázdne* → Output: *prázdne*.
3. Deploy. `vercel.json` zapne čisté URL.

## Architektúra profilu a plánov
- **Jeden profil** (`/profil`) — žiadne oddelené varianty. Rola (hráč / klub / organizácia)
  sa nastavuje v Nastaveniach podľa zvoleného plánu.
- **Pluginy/moduly sa odomykajú podľa plánu**:
  - **Free**: tréningový scoreboard + prihlasovanie do turnajov
  - **Pro / Ultra**: postupne odomyká Club Manager, Tournament Manager, generátor stolov atď.

## Štruktúra
```
/                         landing
/login /registracia       prihlásenie, registrácia
/profil                   JEDEN profil (rola podľa plánu)
/nastavenie-profilu       nastavenia (tu sa volí rola/plán)
/search /upgrade          vyhľadávanie turnajov, predplatné
/ochrana-osobnych-udajov /vymazanie-dat   GDPR

/magazin                  verejný magazín (klasický portál)
/magazin/clanok           detail článku
/cms  /cms/editor         CMS (admin) + blokový editor

/scoreboard               zlúčený scoreboard
/stanice                  launcher staníc (QR)
/manager                  Club Manager dashboard
/manager/rezervacie       rezervácie
```

## Stav
- Frontend-first: dáta v localStorage. Backend (Supabase) sa napája postupne — najprv magazín.
- CMS (`/cms`) je len pre admin.
- Plugin-gating podľa plánu (odomykanie modulov) = logika do ďalšej fázy.
