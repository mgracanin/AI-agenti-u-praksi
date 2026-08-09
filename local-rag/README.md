# Lokalni RAG: n8n + Ollama + Qdrant

Datoteke su pripremljene za n8n 2.33.7, Ollama 0.31.1 i Qdrant 1.19.0.
Portovi su objavljeni samo na `127.0.0.1`; n8n telemetrija i Ollamine cloud
funkcije su isključene.

## Windows 11 — preporučeni način

Koristite Docker Desktop s uključenim WSL 2 backendom i Linux containers
načinom. Projekt držite u kratkoj lokalnoj putanji bez OneDrive sinkronizacije,
primjerice `C:\AI\local-rag`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-windows.ps1
.\verify-windows.ps1
```

Za NVIDIA GPU, ažurirani Windows/WSL/NVIDIA driver i Docker Desktop WSL 2
backend, pokrenite `setup-windows.ps1 -Gpu`. Bez tog parametra sustav radi na
CPU-u i kompatibilan je sa svakim podržanim Windows 11 računalom.

## Pokretanje

```bash
mkdir documents
cp .env.example .env
# uredite .env i postavite dva različita nasumična ključa
docker compose up -d
docker compose exec ollama ollama pull qwen3:8b
docker compose exec ollama ollama pull qwen3-embedding:0.6b
docker compose ps
```

Otvorite `http://localhost:5678`, napravite vlasnički račun i uvezite:

1. `rag-01-ingest.json`
2. `rag-02-chat.json`

U n8n-u napravite Ollama credential s URL-om `http://ollama:11434` i Qdrant
credential s URL-om `http://qdrant:6333` te ključem iz `.env`. U oba workflowa
pridružite te credentiale svim odgovarajućim čvorovima.

Dokumente kopirajte u `documents/`, ručno pokrenite ingest workflow, a zatim u
chat workflowu kliknite **Chat** i testirajte pitanje na koje odgovor postoji te
pitanje na koje odgovor ne postoji.

Ponovno pokretanje ingest workflowa dodaje nove vektore. Za čistu ponovnu
izgradnju tijekom ovog vodiča izbrišite kolekciju `lokalni_dokumenti_v1` kroz
Qdrant Dashboard (`http://localhost:6333/dashboard`) i zatim ponovno pokrenite
ingest. U produkciji umjesto toga uvedite determinističke point ID-eve ili
brisanje po `source_name`/`checksum` metapodatku.
