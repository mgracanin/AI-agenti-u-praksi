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
    throw 'Nije pronađen Python Launcher (py.exe). Instalirajte 64-bitni Python 3.11 pa ponovno pokrenite skriptu.'
}

Assert-PowerShellSyntax @('setup-windows.ps1', 'run-windows.ps1', 'register-task-windows.ps1')

Write-Step 'Provjera Pythona 3.11'
& py.exe -3.11 -c "import sys; print(sys.version); assert sys.version_info[:2] == (3, 11)"
if ($LASTEXITCODE -ne 0) {
    throw 'Python 3.11 nije dostupan. Provjerite naredbom: py -0p'
}

if (-not (Test-Path '.venv\Scripts\python.exe')) {
    Write-Step 'Izrada virtualnog okruženja'
    & py.exe -3.11 -m venv .venv
    if ($LASTEXITCODE -ne 0) { throw 'Izrada .venv nije uspjela.' }
}

$Python = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'

Write-Step 'Instalacija zaključanih ovisnosti'
& $Python -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) { throw 'Nadogradnja pipa nije uspjela.' }
& $Python -m pip install -r requirements.txt
if ($LASTEXITCODE -ne 0) { throw 'Instalacija requirements.txt nije uspjela.' }

if (-not (Test-Path '.env')) {
    Copy-Item '.env.example' '.env'
    Write-Host 'Napravljen je .env. Upišite OPENAI_API_KEY prije pokretanja.' -ForegroundColor Yellow
}

New-Item -ItemType Directory -Path '.data', 'out' -Force | Out-Null

Write-Step 'Provjera koda i testovi'
& $Python -m ruff check .
if ($LASTEXITCODE -ne 0) { throw 'Ruff provjera nije prošla.' }
& $Python -m pytest -q
if ($LASTEXITCODE -ne 0) { throw 'Testovi nisu prošli.' }

Write-Host "`nPriprema je završena." -ForegroundColor Green
Write-Host 'Sljedeće: credentials.json, OPENAI_API_KEY u .env, zatim .\run-windows.ps1'
