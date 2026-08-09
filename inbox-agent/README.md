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
3. Stavite Desktop OAuth datoteku u `credentials.json`, a OpenAI ključ u `.env`.
4. Prvi test pokrenite s `.\run-windows.ps1`; to je dry-run.
5. Tek nakon pregleda pokrenite `.\run-windows.ps1 -Apply`.
6. Zadatak za 07:30 pon–pet registrirajte tek na kraju pomoću
   `.\register-task-windows.ps1`.

Registrirani zadatak koristi račun trenutačnog korisnika i pokreće se samo dok
je taj korisnik prijavljen. Time se ne sprema Windows lozinka i izbjegavaju se
problemi s OAuth profilom. Ako računalo u 07:30 spava, uključena je opcija
`StartWhenAvailable` pa se zadatak pokreće nakon buđenja i prijave.

Skripte uvijek koriste `.venv\Scripts\python.exe`, pa ne ovise o PATH-u ni o
aktiviranom virtualnom okruženju.

## Brzi početak

1. U Google Cloudu uključite Gmail API, konfigurirajte OAuth consent screen,
   izradite OAuth Client ID tipa **Desktop app** i spremite ga kao
   `credentials.json` u korijen projekta.
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
