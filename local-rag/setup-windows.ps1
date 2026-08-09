[CmdletBinding()]
param(
    [switch]$Gpu
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Set-Location $PSScriptRoot

function Write-Step([string]$Text) {
    Write-Host "`n==> $Text" -ForegroundColor Cyan
}

function Assert-PowerShellSyntax([string[]]$Paths) {
    foreach ($Path in $Paths) {
        $Tokens = $null
        $ParseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $PSScriptRoot $Path),
            [ref]$Tokens,
            [ref]$ParseErrors
        ) | Out-Null
        if ($ParseErrors.Count -gt 0) {
            throw "PowerShell sintaksa nije valjana u ${Path}: $($ParseErrors[0].Message)"
        }
    }
}

function New-HexSecret {
    $Bytes = New-Object byte[] 32
    $Rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $Rng.GetBytes($Bytes) } finally { $Rng.Dispose() }
    return ([BitConverter]::ToString($Bytes)).Replace('-', '').ToLowerInvariant()
}

if ($env:OS -ne 'Windows_NT') {
    throw 'Ova je skripta namijenjena Windowsu 11.'
}
if (-not (Get-Command docker.exe -ErrorAction SilentlyContinue)) {
    throw 'Docker CLI nije pronađen. Instalirajte i pokrenite Docker Desktop s WSL 2 backendom.'
}

Assert-PowerShellSyntax @('setup-windows.ps1', 'verify-windows.ps1')

Write-Step 'Provjera Docker Desktopa i Composea'
& docker.exe info *> $null
if ($LASTEXITCODE -ne 0) { throw 'Docker Desktop nije pokrenut ili Linux engine nije dostupan.' }
& docker.exe compose version
if ($LASTEXITCODE -ne 0) { throw 'Docker Compose v2 nije dostupan.' }

if ($PSScriptRoot -match 'OneDrive') {
    Write-Warning 'Projekt je u OneDrive putanji. Premjestite ga, primjerice, u C:\AI\local-rag zbog pouzdanijih bind mountova.'
}

New-Item -ItemType Directory -Path 'documents' -Force | Out-Null
if (-not (Test-Path '.env')) {
    $EnvText = Get-Content '.env.example' -Raw
    $EnvText = $EnvText.Replace('zamijenite_dugim_nasumicnim_kljucem', (New-HexSecret))
    $EnvText = $EnvText.Replace('zamijenite_drugim_dugim_nasumicnim_kljucem', (New-HexSecret))
    [IO.File]::WriteAllText((Join-Path $PSScriptRoot '.env'), $EnvText, [Text.UTF8Encoding]::new($false))
    Write-Host 'Napravljen je .env s dva različita nasumična ključa.' -ForegroundColor Green
}

$CurrentEnv = Get-Content '.env' -Raw
if ($CurrentEnv -match 'zamijenite_') {
    throw '.env još sadrži predložene vrijednosti. Obrišite .env i ponovno pokrenite skriptu ili ručno postavite ključeve.'
}

$Ports = @(5678, 6333, 11434)
foreach ($Port in $Ports) {
    $Listener = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue
    if ($Listener) {
        $Existing = (& docker.exe compose ps -q 2>$null)
        if (-not $Existing) { throw "TCP port $Port već koristi drugi proces." }
    }
}

$ComposeArgs = @('compose')
if ($Gpu) {
    if (-not (Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue)) {
        throw 'Parametar -Gpu traži NVIDIA GPU i ažurirani NVIDIA Windows driver; nvidia-smi.exe nije pronađen.'
    }
    & wsl.exe --status *> $null
    if ($LASTEXITCODE -ne 0) { throw 'WSL 2 nije spreman. Pokrenite wsl --install ili wsl --update kao administrator.' }
    $ComposeArgs += @('-f', 'compose.yaml', '-f', 'compose.gpu.yaml')
}

Write-Step 'Provjera Compose konfiguracije'
& docker.exe @ComposeArgs config -q
if ($LASTEXITCODE -ne 0) { throw 'Compose konfiguracija nije valjana.' }

Write-Step 'Pokretanje n8n, Ollame i Qdranta'
& docker.exe @ComposeArgs up -d
if ($LASTEXITCODE -ne 0) { throw 'Pokretanje kontejnera nije uspjelo.' }

Write-Step 'Preuzimanje lokalnih modela'
& docker.exe @ComposeArgs exec -T ollama ollama pull qwen3:8b
if ($LASTEXITCODE -ne 0) { throw 'Preuzimanje qwen3:8b nije uspjelo.' }
& docker.exe @ComposeArgs exec -T ollama ollama pull qwen3-embedding:0.6b
if ($LASTEXITCODE -ne 0) { throw 'Preuzimanje embedding modela nije uspjelo.' }

Write-Host "`nStack je pokrenut." -ForegroundColor Green
Write-Host '1. Pokrenite .\verify-windows.ps1'
Write-Host '2. Otvorite http://localhost:5678'
Write-Host '3. Uvezite rag-01-ingest.json i rag-02-chat.json'
