[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Set-Location $PSScriptRoot

if (-not (Test-Path '.env')) { throw 'Nedostaje .env. Pokrenite setup-windows.ps1.' }

$Expected = @('n8n', 'ollama', 'qdrant')
$Running = @(& docker.exe compose ps --status running --services)
foreach ($Service in $Expected) {
    if ($Running -notcontains $Service) { throw "Servis '$Service' nije u stanju running." }
}

$Ollama = Invoke-RestMethod -Uri 'http://localhost:11434/api/tags' -TimeoutSec 15
$Names = @($Ollama.models | ForEach-Object { $_.name })
foreach ($Model in @('qwen3:8b', 'qwen3-embedding:0.6b')) {
    if (-not ($Names | Where-Object { $_ -eq $Model -or $_ -like "$Model*" })) {
        throw "Ollama ne popisuje model '$Model'."
    }
}

$ApiKeyLine = Get-Content '.env' | Where-Object { $_ -match '^QDRANT_API_KEY=' } | Select-Object -First 1
if (-not $ApiKeyLine) { throw 'QDRANT_API_KEY nije pronađen u .env.' }
$ApiKey = $ApiKeyLine.Substring('QDRANT_API_KEY='.Length).Trim()
$Headers = @{ 'api-key' = $ApiKey }
$Qdrant = Invoke-RestMethod -Uri 'http://localhost:6333/collections' -Headers $Headers -TimeoutSec 15
if ($null -eq $Qdrant.result) { throw 'Qdrant odgovor nema očekivano polje result.' }

$N8n = Invoke-WebRequest -Uri 'http://localhost:5678' -UseBasicParsing -TimeoutSec 15
if ($N8n.StatusCode -ne 200) { throw "n8n je vratio HTTP $($N8n.StatusCode)." }

& docker.exe compose exec -T n8n sh -lc 'test -d /files && test -r /files && ls -la /files'
if ($LASTEXITCODE -ne 0) { throw 'n8n kontejner ne može čitati /files.' }

Write-Host 'Windows 11 provjera je prošla:' -ForegroundColor Green
Write-Host '- n8n, Ollama i Qdrant su running'
Write-Host '- oba Ollama modela postoje'
Write-Host '- Qdrant prihvaća API ključ'
Write-Host '- n8n odgovara i može čitati documents mapu'
