# Windows 11 — krenite odavde

Paket je pripremljen za Windows 11. Postoje dva odvojena projekta:

- `inbox-agent` — LangGraph obrada Gmaila u nativnom Pythonu;
- `local-rag` — n8n + Ollama + Qdrant u Linux kontejnerima kroz Docker Desktop.

## 1. LangGraph obrada Gmaila

Preduvjet je 64-bitni Python 3.11. Provjerite ga u PowerShellu:

```powershell
py -3.11 --version
```

Zatim:

```powershell
Set-Location C:\AI\AI-agenti-u-praksi\inbox-agent
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-windows.ps1
```

Dodajte `credentials.json`, upišite `OPENAI_API_KEY` u `.env` i pokrenite:

```powershell
.\run-windows.ps1
```

To je dry-run i ne mijenja Gmail. Tek nakon pregleda:

```powershell
.\run-windows.ps1 -Apply
```

Raspored 07:30 pon–pet registrira se zasebno:

```powershell
.\register-task-windows.ps1
```

Skripte izravno koriste `.venv\Scripts\python.exe`; aktivacija virtualnog
okruženja i promjena PowerShell Execution Policy nisu potrebne. `tzdata` je
uključen kako bi `Europe/Zagreb` radio i na Windowsu.

## 2. Lokalni n8n + Ollama + Qdrant

Otvorite PowerShell kao administrator i instalirajte/ažurirajte WSL 2:

```powershell
wsl --install
wsl --update
wsl --version
```

Nakon eventualnog restarta instalirajte Docker Desktop. U njegovim postavkama
uključite **Use the WSL 2 based engine** i ostavite **Linux containers** način.

Projekt raspakirajte u kratku lokalnu putanju koja nije pod OneDriveom,
primjerice `C:\AI\AI-agenti-u-praksi\local-rag`.

CPU način, kompatibilan sa svakim podržanim Windows 11 računalom:

```powershell
Set-Location C:\AI\AI-agenti-u-praksi\local-rag
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-windows.ps1
.\verify-windows.ps1
```

NVIDIA GPU način traži ažuriran Windows, WSL, NVIDIA driver i Docker Desktop s
WSL 2 backendom:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-windows.ps1 -Gpu
.\verify-windows.ps1
```

Nakon uspješne provjere otvorite `http://localhost:5678`, napravite vlasnički
račun, uvezite `rag-01-ingest.json` i `rag-02-chat.json`, pa pridružite:

- Ollama credential: `http://ollama:11434`;
- Qdrant credential: `http://qdrant:6333` i ključ iz `.env`.

Dokumente kopirajte u `local-rag\documents`. Skripta za provjeru potvrđuje da su
sva tri kontejnera pokrenuta, oba modela preuzeta, Qdrant ključ valjan, n8n
dostupan i mapa `documents` čitljiva iz n8n kontejnera.

## Tipične Windows pogreške

| Simptom | Rješenje |
|---|---|
| `docker` nije pronađen | Pokrenite Docker Desktop i otvorite novi PowerShell. |
| Docker prikazuje Windows containers | Prebacite se na Linux containers. |
| WSL nije spreman | Kao administrator pokrenite `wsl --install`, zatim `wsl --update` i restart. |
| Port 5678, 6333 ili 11434 je zauzet | Zaustavite proces koji ga koristi; setup skripta prijavljuje točan port. |
| n8n ne vidi Ollamu/Qdrant | U credentialu koristite `ollama`/`qdrant`, ne `localhost`. |
| n8n ne vidi dokumente | Izbjegnite OneDrive putanju i provjerite rezultat `verify-windows.ps1`. |
| GPU način ne radi | Ažurirajte NVIDIA Windows driver i WSL; prvo potvrdite da CPU način radi. |
| `Europe/Zagreb` nije pronađen | Ponovno pokrenite `setup-windows.ps1`; `tzdata==2026.3` mora biti instaliran. |
