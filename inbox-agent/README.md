# LangGraph obrada Gmaila

Sigurna početna izvedba jutarnje obrade pošte. Zadani način je `--dry-run` i ne
mijenja Gmail. `--apply` može napraviti samo skicu odgovora i dodati oznake;
u projektu namjerno ne postoji metoda za slanje poruke. Kalendarski podaci ostaju
prijedlog u lokalnom Markdown sažetku.

## Windows 11 — preporučeni način

Projekt je pripremljen za Windows 11 i Python 3.11. Paket `tzdata` uključen je
jer Windows nema IANA bazu vremenskih zona koju Pythonov `zoneinfo` očekuje za
`Europe/Zagreb`. Nije potrebno aktivirati virtualno okruženje niti mijenjati
PowerShell Execution Policy.

1. Instalirajte 64-bitni Python 3.11 i potvrdite `py -3.11 --version`.
2. Pokrenite `powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-windows.ps1`.
3. Konfigurirajte Gmail OAuth prema postupku u odjeljku **Konfiguracija Gmail OAutha i credentials.json** ispod.
4. Kopirajte `.env.example` u `.env` i upišite svoj `OPENAI_API_KEY`.
5. Prvi test pokrenite s `.\run-windows.ps1`; to je dry-run. Pri prvom pokretanju otvorit će se web-preglednik za Googleovu OAuth autorizaciju.
6. Tek nakon pregleda pokrenite `.\run-windows.ps1 -Apply`.
7. Zadatak za 07:30 pon–pet registrirajte tek na kraju pomoću `.\register-task-windows.ps1`.

Registrirani zadatak koristi račun trenutačnog korisnika i pokreće se samo dok
je taj korisnik prijavljen. Time se ne sprema Windows lozinka i izbjegavaju se
problemi s OAuth profilom. Ako računalo u 07:30 spava, uključena je opcija
`StartWhenAvailable` pa se zadatak pokreće nakon buđenja i prijave.

Skripte uvijek koriste `.venv\Scripts\python.exe`, pa ne ovise o PATH-u ni o
aktiviranom virtualnom okruženju.

## Konfiguracija Gmail OAutha i `credentials.json`

`credentials.json` nije Gmail lozinka niti OAuth token korisnika. To je JSON
datoteka koja sadrži identitet OAuth klijenta (`client_id` i `client_secret`)
koji izradite u Google Cloudu. Korisnik se zasebno prijavljuje u Google i daje
pristanak za pristup Gmailu. Nakon prvog uspješnog OAuth postupka aplikacija
sprema korisnički token u `.data/token.json` i kasnije ga koristi za obnavljanje
pristupa bez ponovne prijave dok je refresh token valjan.

### 1. Izradite ili odaberite Google Cloud projekt

Otvorite Google Cloud Console na https://console.cloud.google.com/ i izradite
novi projekt ili odaberite postojeći projekt koji želite koristiti samo za ovaj
agent. Preporučljivo je ne koristiti produkcijski projekt neke druge aplikacije.

### 2. Uključite Gmail API

U odabranom projektu otvorite **APIs & Services > Library**, pronađite
**Gmail API** i kliknite **Enable**.

Službeni Gmail Python quickstart:
https://developers.google.com/workspace/gmail/api/quickstart/python

### 3. Konfigurirajte Google Auth Platform

U Google Cloud Consoleu otvorite **Google Auth Platform**. Ako projekt još nema
konfiguriran OAuth consent screen, kliknite **Get Started**.

U dijelu **Branding** postavite barem:

- **App name** — primjerice `AI Inbox Agent`;
- **User support email** — svoju adresu e-pošte;
- **Developer contact information** — adresu na koju Google može slati obavijesti o projektu.

U dijelu **Audience** odaberite odgovarajući tip korisnika:

- za obični osobni Gmail račun (`@gmail.com`) odaberite **External**;
- ako projekt pripada Google Workspace organizaciji i agent će koristiti samo korisnici te organizacije, možete odabrati **Internal**.

Ako koristite **External** i aplikacija je u statusu **Testing**, u
**Audience > Test users** dodajte Gmail račun s kojim ćete pokretati agenta.
Bez toga OAuth autorizacija za testnog korisnika može biti odbijena.

Googleove aktualne upute za consent screen:
https://developers.google.com/workspace/marketplace/configure-oauth-consent-screen

### 4. Dodajte Gmail scopeove koje agent koristi

U **Google Auth Platform > Data Access** dodajte scopeove koje trenutačna
implementacija traži:

```text
https://www.googleapis.com/auth/gmail.modify
https://www.googleapis.com/auth/gmail.compose
```

Google oba scopea klasificira kao **Restricted**. `gmail.modify` omogućuje
čitanje i izmjenu poruka, a `gmail.compose` upravljanje skicama. Googleov opis
tih scopeova dopušta i slanje e-pošte, ali ova aplikacija namjerno nema metodu
koja poziva Gmail API za slanje poruke; `--apply` izrađuje samo skice i oznake.

Popis i klasifikacija Gmail scopeova:
https://developers.google.com/workspace/gmail/api/auth/scopes

Ako ovu aplikaciju kasnije namjeravate distribuirati širem krugu korisnika,
restricted scopeovi mogu zahtijevati Googleovu OAuth verifikaciju i dodatne
sigurnosne zahtjeve. Za osobni razvoj i testiranje nemojte nepotrebno objavljivati
OAuth aplikaciju.

### 5. Izradite OAuth Client ID tipa Desktop app

Otvorite **Google Auth Platform > Clients** i odaberite **Create Client**.
Postavite:

- **Application type:** `Desktop app`;
- **Name:** primjerice `AI Inbox Agent Windows`.

Kliknite **Create**, zatim preuzmite JSON datoteku OAuth klijenta. Preuzeta
datoteka često ima duži naziv; preimenujte je u:

```text
credentials.json
```

i kopirajte je izravno u direktorij `inbox-agent`, tako da struktura izgleda
ovako:

```text
inbox-agent\
  credentials.json
  .env
  run-windows.ps1
  setup-windows.ps1
  register-task-windows.ps1
```

Za Desktop app ne trebate ručno upisivati redirect URI. Kod koristi
`InstalledAppFlow.run_local_server(port=0)`, pa Python pri autorizaciji pokrene
privremeni lokalni HTTP callback na slobodnom portu i otvori zadani web-preglednik.

`credentials.json` sadrži povjerljive podatke i ne smije se commitati. Projektni
`.gitignore` već ignorira `inbox-agent/credentials.json`, `.env`, `.data/` i
`out/`, ali svejedno prije svakog commita provjerite `git status`.

### 6. Pokrenite prvu OAuth autorizaciju

Iz direktorija `inbox-agent` pokrenite:

```powershell
.\run-windows.ps1
```

To je zadano `--dry-run` pokretanje. Ako `.data/token.json` još ne postoji,
aplikacija će otvoriti web-preglednik. Prijavite se Gmail računom koji ste
odabrali kao testnog korisnika, pregledajte tražene dozvole i potvrdite pristup.
Google zatim vraća autorizaciju na lokalni callback, a aplikacija sprema token u:

```text
inbox-agent\.data\token.json
```

`token.json` sadrži korisničke OAuth tokene. Ne kopirajte ga na druga računala,
ne šaljite ga drugim korisnicima i ne commitajte ga u Git.

Pri sljedećim pokretanjima aplikacija koristi spremljeni refresh token i po
potrebi automatski obnavlja kratkotrajni access token.

### 7. Važno za External aplikacije u statusu Testing

Google za OAuth projekt tipa **External** koji ima publishing status
**Testing** izdaje refresh token koji u pravilu istječe nakon 7 dana ako
aplikacija traži scopeove izvan osnovnih `openid/profile/email` scopeova. Ovaj
agent koristi Gmail restricted scopeove, pa je to važno ako želite da Scheduled
Task radi kontinuirano bez ponovne autorizacije.

Ako token istekne, ponovno pokrenite `run-windows.ps1` interaktivno i ponovite
OAuth autorizaciju. Za dugotrajniju uporabu potrebno je odgovarajuće urediti
publishing/verifikacijski status OAuth aplikacije u skladu s Googleovim
pravilima.

Googleova dokumentacija o isteku refresh tokena:
https://developers.google.com/identity/protocols/oauth2#expiration

### 8. Kada treba obrisati `token.json`

Izbrišite `.data/token.json` i ponovno provedite OAuth autorizaciju ako:

- promijenite `credentials.json` odnosno OAuth Client ID;
- promijenite Gmail scopeove koje aplikacija traži;
- želite autorizirati drugi Gmail račun;
- Google vrati `invalid_grant` ili je korisnik opozvao pristup aplikaciji.

Nakon brisanja tokena sljedeće pokretanje ponovno će otvoriti Googleovu OAuth
autorizaciju.

## Brzi početak

1. U Google Cloudu uključite Gmail API i dovršite postupak iz odjeljka **Konfiguracija Gmail OAutha i credentials.json**.
2. Kopirajte `.env.example` u `.env` i upišite `OPENAI_API_KEY`.
3. Napravite virtualno okruženje i instalirajte ovisnosti:

   ```bash
   python -m venv .venv
   # Linux/macOS
   source .venv/bin/activate
   # Windows PowerShell nije potrebno aktivirati; setup-windows.ps1 poziva
   # interpreter iz .venv izravno.
   python -m pip install --upgrade pip
   python -m pip install -r requirements.txt
   ```

4. Pokrenite provjere i prvi dry-run:

   ```bash
   python -m pytest
   python -m ruff check .
   python -m inbox_agent --dry-run
   ```

5. Pregledajte lokalni sažetak u `out/`, pa tek zatim dopustite izradu skica:

   ```bash
   python -m inbox_agent --apply
   ```

Za obradu jedne testne poruke upotrijebite
`python -m inbox_agent --dry-run --message-id GMAIL_MESSAGE_ID`.

## Zakazivanje

Nakon nekoliko uspješnih ručnih pokretanja zakažite naredbu
`python -m inbox_agent --apply` za 07:30 radnim danom kroz cron ili Windows Task
Scheduler. Radni direktorij mora biti korijen projekta, a zadatak mora koristiti
Python iz `.venv`.
