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

$script:CurrentStep = 'Pokretanje'
$script:Remediation = 'Provjerite poruku o pogrešci i zapis izvođenja pa ponovno pokrenite skriptu.'
$ExitCode = 1
$Log = $null

function Fail([string]$Message, [string]$Fix) { $script:Remediation = $Fix; throw $Message }
function Test-EnvValue([string]$Name) {
    if (-not (Test-Path '.env' -PathType Leaf)) { return $false }
    $Line = Get-Content '.env' | Where-Object { $_ -match "^$([regex]::Escape($Name))=" } | Select-Object -First 1
    if (-not $Line) { return $false }
    return (-not [string]::IsNullOrWhiteSpace($Line.Substring($Name.Length + 1).Trim()))
}

try {
    $script:CurrentStep = 'Preflight i dependency report'
    $Python = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
    $Checks = @(
        [pscustomobject]@{ Dependency='Windows'; Status=$(if ($env:OS -eq 'Windows_NT') {'OK'} else {'FAIL'}); Details=$env:OS },
        [pscustomobject]@{ Dependency='.venv Python'; Status=$(if (Test-Path $Python -PathType Leaf) {'OK'} else {'FAIL'}); Details=$Python },
        [pscustomobject]@{ Dependency='credentials.json'; Status=$(if (Test-Path 'credentials.json' -PathType Leaf) {'OK'} else {'FAIL'}); Details='Google Desktop OAuth' },
        [pscustomobject]@{ Dependency='.env'; Status=$(if (Test-Path '.env' -PathType Leaf) {'OK'} else {'FAIL'}); Details='Konfiguracija' },
        [pscustomobject]@{ Dependency='OPENAI_API_KEY'; Status=$(if (Test-EnvValue 'OPENAI_API_KEY') {'OK'} else {'FAIL'}); Details='Vrijednost postoji; sadržaj se ne ispisuje.' }
    )
    $Checks | Format-Table -AutoSize | Out-Host
    if ($Checks.Status -contains 'FAIL') { Fail 'Jedan ili više runtime preduvjeta nisu zadovoljeni.' 'Pokrenite .\setup-windows.ps1, dodajte credentials.json i upišite OPENAI_API_KEY u .env.' }

    $script:CurrentStep = 'Validacija credentials.json'
    try { $Credentials = Get-Content 'credentials.json' -Raw | ConvertFrom-Json } catch { Fail 'credentials.json nije valjan JSON.' 'Preuzmite novu Desktop OAuth JSON datoteku iz Google Cloud Consolea.' }
    $Installed = $null
    if ($Credentials.PSObject.Properties.Name -contains 'installed') { $Installed = $Credentials.installed }
    $HasClientId = ($Installed -and ($Installed.PSObject.Properties.Name -contains 'client_id') -and -not [string]::IsNullOrWhiteSpace([string]$Installed.client_id))
    $HasClientSecret = ($Installed -and ($Installed.PSObject.Properties.Name -contains 'client_secret') -and -not [string]::IsNullOrWhiteSpace([string]$Installed.client_secret))
    if (-not $HasClientId -or -not $HasClientSecret) {
        Fail 'credentials.json ne izgleda kao Google Desktop OAuth konfiguracija.' 'U Google Cloud Consoleu izradite OAuth Client ID tipa Desktop app i preuzmite JSON.'
    }

    $Arguments = @('-m', 'inbox_agent', '--limit', $Limit)
    if ($Apply) { $Arguments += '--apply'; Write-Host 'APPLY: dopuštena je izrada Gmail nacrta i oznaka; slanje nije implementirano.' -ForegroundColor Yellow }
    else { $Arguments += '--dry-run'; Write-Host 'DRY-RUN: Gmail se neće mijenjati.' -ForegroundColor Green }
    if ($MessageId) { $Arguments += @('--message-id', $MessageId) }

    New-Item -ItemType Directory -Path 'out' -Force | Out-Null
    $Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $Log = Join-Path $PSScriptRoot "out\windows-$Stamp.log"

    $script:CurrentStep = 'Pokretanje Inbox Agenta'
    & $Python @Arguments 2>&1 | Tee-Object -FilePath $Log
    $ExitCode = $LASTEXITCODE
    if ($ExitCode -ne 0) { Fail "Inbox Agent završio je s exit codeom $ExitCode." "Otvorite zapis izvođenja: $Log" }

    Write-Host "Zapis izvođenja: $Log"
    exit 0
}
catch {
    Write-Host "`nIZVOĐENJE NIJE USPJELO" -ForegroundColor Red
    Write-Host "FAILED STEP: $script:CurrentStep" -ForegroundColor Red
    Write-Host "CAUSE: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "HOW TO FIX: $script:Remediation" -ForegroundColor Yellow
    if ($Log) { Write-Host "LOG: $Log" -ForegroundColor Yellow }
    exit $(if ($ExitCode -gt 0) { $ExitCode } else { 1 })
}
