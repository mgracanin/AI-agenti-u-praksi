[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Set-Location $PSScriptRoot

$script:CurrentStep = 'Pokretanje'
$script:Remediation = 'Provjerite prijavljeni problem i ponovno pokrenite provjeru.'
function Fail([string]$Message, [string]$Fix) { $script:Remediation = $Fix; throw $Message }

try {
    $script:CurrentStep = 'Preflight i dependency report'
    $Docker = Get-Command docker.exe -ErrorAction SilentlyContinue
    $DockerEngineOk = $false
    $ComposeOk = $false
    if ($Docker) {
        & docker.exe info *> $null
        $DockerEngineOk = ($LASTEXITCODE -eq 0)
        & docker.exe compose version *> $null
        $ComposeOk = ($LASTEXITCODE -eq 0)
    }
    $Checks = @(
        [pscustomobject]@{ Dependency='Windows'; Status=$(if ($env:OS -eq 'Windows_NT') {'OK'} else {'FAIL'}); Details=$env:OS },
        [pscustomobject]@{ Dependency='Docker CLI'; Status=$(if ($Docker) {'OK'} else {'FAIL'}); Details=$(if ($Docker) {$Docker.Source} else {'docker.exe nije u PATH-u.'}) },
        [pscustomobject]@{ Dependency='Docker Linux engine'; Status=$(if ($DockerEngineOk) {'OK'} else {'FAIL'}); Details=$(if ($DockerEngineOk) {'Dostupan.'} else {'Nije dostupan.'}) },
        [pscustomobject]@{ Dependency='Docker Compose v2'; Status=$(if ($ComposeOk) {'OK'} else {'FAIL'}); Details=$(if ($ComposeOk) {'Dostupan.'} else {'Nije dostupan.'}) },
        [pscustomobject]@{ Dependency='.env'; Status=$(if (Test-Path '.env' -PathType Leaf) {'OK'} else {'FAIL'}); Details='local-rag konfiguracija' },
        [pscustomobject]@{ Dependency='compose.yaml'; Status=$(if (Test-Path 'compose.yaml' -PathType Leaf) {'OK'} else {'FAIL'}); Details='Compose definicija' }
    )
    $Checks | Format-Table -AutoSize | Out-Host
    if ($Checks.Status -contains 'FAIL') { Fail 'Preflight provjera nije prošla.' 'Pokrenite .\setup-windows.ps1 i ispravite sve stavke označene s FAIL.' }

    $script:CurrentStep = 'Provjera statusa servisa'
    $Expected = @('n8n','ollama','qdrant')
    $Running = @(& docker.exe compose ps --status running --services)
    if ($LASTEXITCODE -ne 0) { Fail 'Nije moguće dohvatiti status Compose servisa.' 'Pokrenite docker compose ps i riješite prijavljenu Docker pogrešku.' }
    foreach ($Service in $Expected) {
        if ($Running -notcontains $Service) { Fail "Servis '$Service' nije u stanju running." "Pokrenite docker compose ps i docker compose logs $Service. Zatim ispravite uzrok i ponovno pokrenite provjeru." }
    }

    $script:CurrentStep = 'Ollama API i modeli'
    try { $Ollama = Invoke-RestMethod -Uri 'http://localhost:11434/api/tags' -TimeoutSec 15 } catch { Fail "Ollama API nije dostupan: $($_.Exception.Message)" 'Provjerite docker compose logs ollama i je li port 11434 dostupan.' }
    $Names = @($Ollama.models | ForEach-Object { $_.name })
    foreach ($Model in @('qwen3:8b','qwen3-embedding:0.6b')) {
        if (-not ($Names | Where-Object { $_ -eq $Model -or $_ -like "$Model*" })) { Fail "Ollama ne popisuje model '$Model'." "Pokrenite: docker compose exec -T ollama ollama pull $Model" }
    }

    $script:CurrentStep = 'Qdrant API'
    $ApiKeyLine = Get-Content '.env' | Where-Object { $_ -match '^QDRANT_API_KEY=' } | Select-Object -First 1
    if (-not $ApiKeyLine) { Fail 'QDRANT_API_KEY nije pronađen u .env.' 'Ponovno generirajte .env pomoću setup-windows.ps1 ili dodajte QDRANT_API_KEY.' }
    $ApiKey = $ApiKeyLine.Substring('QDRANT_API_KEY='.Length).Trim()
    if ([string]::IsNullOrWhiteSpace($ApiKey)) { Fail 'QDRANT_API_KEY u .env je prazan.' 'Postavite neprazan QDRANT_API_KEY i ponovno pokrenite stack.' }
    try { $Qdrant = Invoke-RestMethod -Uri 'http://localhost:6333/collections' -Headers @{ 'api-key'=$ApiKey } -TimeoutSec 15 } catch { Fail "Qdrant API provjera nije uspjela: $($_.Exception.Message)" 'Provjerite docker compose logs qdrant, API ključ i port 6333.' }
    if ($null -eq $Qdrant.result) { Fail 'Qdrant odgovor nema očekivano polje result.' 'Provjerite verziju Qdranta i njegov API odgovor.' }

    $script:CurrentStep = 'n8n HTTP provjera'
    try { $N8n = Invoke-WebRequest -Uri 'http://localhost:5678' -UseBasicParsing -TimeoutSec 15 } catch { Fail "n8n nije dostupan: $($_.Exception.Message)" 'Provjerite docker compose logs n8n i port 5678.' }
    if ($N8n.StatusCode -ne 200) { Fail "n8n je vratio HTTP $($N8n.StatusCode)." 'Provjerite n8n logove i konfiguraciju.' }

    $script:CurrentStep = 'n8n pristup /files'
    & docker.exe compose exec -T n8n sh -lc 'test -d /files && test -r /files && ls -la /files'
    if ($LASTEXITCODE -ne 0) { Fail 'n8n kontejner ne može čitati /files.' 'Provjerite bind mount ./documents:/files:ro, putanju projekta i Docker Desktop file sharing.' }

    Write-Host 'Windows 11 provjera je prošla:' -ForegroundColor Green
    Write-Host '- Docker engine i Compose v2 su dostupni'
    Write-Host '- n8n, Ollama i Qdrant su running'
    Write-Host '- oba Ollama modela postoje'
    Write-Host '- Qdrant prihvaća API ključ'
    Write-Host '- n8n odgovara i može čitati documents mapu'
    exit 0
}
catch {
    Write-Host "`nVALIDACIJA NIJE PROŠLA" -ForegroundColor Red
    Write-Host "FAILED STEP: $script:CurrentStep" -ForegroundColor Red
    Write-Host "CAUSE: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "HOW TO FIX: $script:Remediation" -ForegroundColor Yellow
    exit 1
}
