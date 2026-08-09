[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$MessageId,
    [ValidateRange(1, 100)]
    [int]$Limit = 20
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Set-Location $PSScriptRoot

$Python = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
if (-not (Test-Path $Python)) {
    throw 'Nedostaje .venv. Prvo pokrenite .\setup-windows.ps1.'
}
if (-not (Test-Path 'credentials.json')) {
    throw 'Nedostaje credentials.json (Google Desktop OAuth datoteka).'
}
if (-not (Test-Path '.env')) {
    throw 'Nedostaje .env. Prvo pokrenite .\setup-windows.ps1 i upišite OPENAI_API_KEY.'
}

$Arguments = @('-m', 'inbox_agent', '--limit', $Limit)
if ($Apply) {
    $Arguments += '--apply'
    Write-Host 'APPLY: dopuštena je izrada Gmail nacrta i oznaka; slanje nije implementirano.' -ForegroundColor Yellow
} else {
    $Arguments += '--dry-run'
    Write-Host 'DRY-RUN: Gmail se neće mijenjati.' -ForegroundColor Green
}
if ($MessageId) {
    $Arguments += @('--message-id', $MessageId)
}

New-Item -ItemType Directory -Path 'out' -Force | Out-Null
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Log = Join-Path $PSScriptRoot "out\windows-$Stamp.log"

& $Python @Arguments 2>&1 | Tee-Object -FilePath $Log
$ExitCode = $LASTEXITCODE
Write-Host "Zapis izvođenja: $Log"
exit $ExitCode
