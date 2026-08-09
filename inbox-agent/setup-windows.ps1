[CmdletBinding()]
param()

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

if ($env:OS -ne 'Windows_NT') {
    throw 'Ova je skripta namijenjena Windowsu 11.'
}

if (-not (Get-Command py.exe -ErrorAction SilentlyContinue)) {
    throw 'Nije pronađen Python Launcher (py.exe). Instalirajte 64-bitni Python 3.10 ili noviji pa ponovno pokrenite skriptu.'
}

Assert-PowerShellSyntax @(
    'setup-windows.ps1',
    'run-windows.ps1',
    'register-task-windows.ps1'
)

Write-Step 'Provjera Pythona 3.10 ili novijeg'

& py.exe -3 -c "import sys; print(sys.version); sys.exit(0 if sys.version_info >= (3, 10) else 1)"

if ($LASTEXITCODE -ne 0) {
    throw 'Nije pronađen odgovarajući Python 3.10 ili noviji. Instalirane verzije provjerite naredbom: py -0p'
}

$VenvPython = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'

if (Test-Path $VenvPython) {
    Write-Step 'Provjera postojećeg virtualnog okruženja'

    & $VenvPython -c "import sys; print(sys.version); sys.exit(0 if sys.version_info >= (3, 10) else 1)"

    if ($LASTEXITCODE -ne 0) {
        Write-Host 'Postojeće .venv okruženje koristi Python stariji od 3.10. Bit će ponovno izrađeno.' -ForegroundColor Yellow

        Remove-Item '.venv' -Recurse -Force
    }
}

if (-not (Test-Path $VenvPython)) {
    Write-Step 'Izrada virtualnog okruženja'

    & py.exe -3 -m venv .venv

    if ($LASTEXITCODE -ne 0) {
        throw 'Izrada .venv nije uspjela.'
    }
}

$Python = $VenvPython

Write-Step 'Instalacija zaključanih ovisnosti'

& $Python -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) {
    throw 'Nadogradnja pipa nije uspjela.'
}

& $Python -m pip install -r requirements.txt
if ($LASTEXITCODE -ne 0) {
    throw 'Instalacija requirements.txt nije uspjela.'
}

if (-not (Test-Path '.env')) {
    Copy-Item '.env.example' '.env'

    Write-Host 'Napravljen je .env. Upišite OPENAI_API_KEY prije pokretanja.' -ForegroundColor Yellow
}

New-Item -ItemType Directory -Path '.data', 'out' -Force | Out-Null

Write-Step 'Provjera koda i testovi'

& $Python -m ruff check .
if ($LASTEXITCODE -ne 0) {
    throw 'Ruff provjera nije prošla.'
}

& $Python -m pytest -q
if ($LASTEXITCODE -ne 0) {
    throw 'Testovi nisu prošli.'
}

Write-Host "`nPriprema je završena." -ForegroundColor Green
Write-Host 'Sljedeće: credentials.json, OPENAI_API_KEY u .env, zatim .\run-windows.ps1'
