[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Set-Location $PSScriptRoot

$script:CurrentStep = 'Pokretanje'
$script:Remediation = 'Provjerite prethodnu poruku o pogrešci i ponovno pokrenite skriptu nakon ispravka.'

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Fail([string]$Message, [string]$Fix) { $script:Remediation = $Fix; throw $Message }
function Add-Check([System.Collections.ArrayList]$List, [string]$Dependency, [bool]$Ok, [string]$Details) {
    [void]$List.Add([pscustomobject]@{ Dependency = $Dependency; Status = $(if ($Ok) { 'OK' } else { 'FAIL' }); Details = $Details })
}
function Assert-PowerShellSyntax([string[]]$Paths) {
    foreach ($Path in $Paths) {
        $FullPath = Join-Path $PSScriptRoot $Path
        if (-not (Test-Path $FullPath -PathType Leaf)) { Fail "Nedostaje $Path." 'Ponovno preuzmite ili raspakirajte cijeli inbox-agent direktorij.' }
        $Tokens = $null; $ParseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($FullPath, [ref]$Tokens, [ref]$ParseErrors) | Out-Null
        if ($ParseErrors.Count -gt 0) { Fail "PowerShell sintaksa nije valjana u ${Path}: $($ParseErrors[0].Message)" 'Vratite izvornu verziju datoteke ili ispravite prijavljenu sintaksnu pogrešku.' }
    }
}

try {
    $script:CurrentStep = 'Preflight i dependency report'
    $Checks = [System.Collections.ArrayList]::new()

    $IsWindows = ($env:OS -eq 'Windows_NT')
    Add-Check $Checks 'Windows 11' $IsWindows $(if ($IsWindows) { [Environment]::OSVersion.VersionString } else { 'Skripta se ne izvodi na Windowsu.' })

    $PyCommand = Get-Command py.exe -ErrorAction SilentlyContinue
    Add-Check $Checks 'Python Launcher (py.exe)' ($null -ne $PyCommand) $(if ($PyCommand) { $PyCommand.Source } else { 'Nije pronađen u PATH-u.' })

    $PythonVersionOk = $false
    $PythonVersionText = 'Nije provjeren jer py.exe nedostaje.'
    if ($PyCommand) {
        $PythonVersionText = (& py.exe -3 -c "import sys; print('.'.join(map(str, sys.version_info[:3]))); sys.exit(0 if sys.version_info >= (3, 10) else 1)" 2>&1 | Out-String).Trim()
        $PythonVersionOk = ($LASTEXITCODE -eq 0)
    }
    Add-Check $Checks 'Python >= 3.10' $PythonVersionOk $PythonVersionText

    foreach ($RequiredFile in @('requirements.txt', '.env.example', 'run-windows.ps1', 'register-task-windows.ps1')) {
        Add-Check $Checks $RequiredFile (Test-Path $RequiredFile -PathType Leaf) $(if (Test-Path $RequiredFile -PathType Leaf) { 'Pronađen.' } else { 'Nedostaje.' })
    }

    $Checks | Format-Table -AutoSize | Out-Host
    if (-not $IsWindows) { Fail 'Ova je skripta namijenjena Windowsu 11.' 'Pokrenite je u Windows PowerShellu na Windowsu 11.' }
    if (-not $PyCommand) { Fail 'Nije pronađen Python Launcher (py.exe).' 'Instalirajte 64-bitni Python 3.10 ili noviji s python.org i uključite Python Launcher.' }
    if (-not $PythonVersionOk) { Fail 'Nije pronađen odgovarajući Python 3.10 ili noviji.' 'Provjerite instalirane verzije naredbom: py -0p' }
    if ($Checks.Status -contains 'FAIL') { Fail 'Jedan ili više preduvjeta nisu zadovoljeni.' 'Ispravite sve stavke označene s FAIL i ponovno pokrenite setup.' }

    Assert-PowerShellSyntax @('setup-windows.ps1', 'run-windows.ps1', 'register-task-windows.ps1')

    $VenvPython = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
    if (Test-Path $VenvPython -PathType Leaf) {
        Write-Step 'Provjera postojećeg virtualnog okruženja'
        $script:CurrentStep = 'Provjera postojećeg .venv okruženja'
        & $VenvPython -c "import sys; print(sys.version); sys.exit(0 if sys.version_info >= (3, 10) else 1)"
        if ($LASTEXITCODE -ne 0) {
            Write-Host 'Postojeće .venv okruženje koristi Python stariji od 3.10. Ponovno ga izrađujem.' -ForegroundColor Yellow
            Remove-Item '.venv' -Recurse -Force
        }
    }

    if (-not (Test-Path $VenvPython -PathType Leaf)) {
        Write-Step 'Izrada virtualnog okruženja'
        $script:CurrentStep = 'Izrada virtualnog okruženja'
        & py.exe -3 -m venv .venv
        if ($LASTEXITCODE -ne 0) { Fail 'Izrada .venv nije uspjela.' 'Provjerite instalaciju Pythona i prava pisanja u direktoriju projekta.' }
    }

    $Python = $VenvPython
    Write-Step 'Instalacija zaključanih ovisnosti'
    $script:CurrentStep = 'Nadogradnja pipa'
    & $Python -m pip install --upgrade pip
    if ($LASTEXITCODE -ne 0) { Fail 'Nadogradnja pipa nije uspjela.' 'Provjerite internetsku vezu, proxy i TLS/CA postavke.' }

    $script:CurrentStep = 'Instalacija requirements.txt'
    & $Python -m pip install -r requirements.txt
    if ($LASTEXITCODE -ne 0) { Fail 'Instalacija requirements.txt nije uspjela.' 'Provjerite internetsku vezu/proxy i sadržaj requirements.txt.' }

    if (-not (Test-Path '.env' -PathType Leaf)) {
        Copy-Item '.env.example' '.env'
        Write-Host 'Napravljen je .env. Upišite OPENAI_API_KEY prije pokretanja.' -ForegroundColor Yellow
    }

    New-Item -ItemType Directory -Path '.data', 'out' -Force | Out-Null

    Write-Step 'Provjera koda i testovi'
    $script:CurrentStep = 'Ruff provjera'
    & $Python -m ruff check .
    if ($LASTEXITCODE -ne 0) { Fail 'Ruff provjera nije prošla.' 'Ispravite prijavljene Python lint pogreške prije pokretanja agenta.' }

    $script:CurrentStep = 'Pytest'
    & $Python -m pytest -q
    if ($LASTEXITCODE -ne 0) { Fail 'Testovi nisu prošli.' 'Ispravite prijavljene testove; setup se ne smatra uspješnim dok pytest ne prođe.' }

    Write-Host "`nPriprema je završena i sve automatske validacije su prošle." -ForegroundColor Green
    Write-Host 'Sljedeće: credentials.json, OPENAI_API_KEY u .env, zatim .\run-windows.ps1'
}
catch {
    Write-Host "`nSETUP NIJE DOVRŠEN" -ForegroundColor Red
    Write-Host "FAILED STEP: $script:CurrentStep" -ForegroundColor Red
    Write-Host "CAUSE: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "HOW TO FIX: $script:Remediation" -ForegroundColor Yellow
    exit 1
}
