[CmdletBinding()]
param([string]$TaskName = 'AI jutarnja obrada Gmaila')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Set-Location $PSScriptRoot

$script:CurrentStep = 'Pokretanje'
$script:Remediation = 'Provjerite prijavljeni preduvjet i ponovno pokrenite skriptu.'
function Fail([string]$Message, [string]$Fix) { $script:Remediation = $Fix; throw $Message }
function Test-EnvValue([string]$Name) {
    if (-not (Test-Path '.env' -PathType Leaf)) { return $false }
    $Line = Get-Content '.env' | Where-Object { $_ -match "^$([regex]::Escape($Name))=" } | Select-Object -First 1
    if (-not $Line) { return $false }
    return (-not [string]::IsNullOrWhiteSpace($Line.Substring($Name.Length + 1).Trim()))
}

try {
    $script:CurrentStep = 'Preflight i dependency report'
    $RequiredCmdlets = @('New-ScheduledTaskAction','New-ScheduledTaskTrigger','New-ScheduledTaskSettingsSet','New-ScheduledTaskPrincipal','Register-ScheduledTask','Get-ScheduledTask')
    $MissingCmdlets = @($RequiredCmdlets | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
    $Checks = @(
        [pscustomobject]@{ Dependency='Windows'; Status=$(if ($env:OS -eq 'Windows_NT') {'OK'} else {'FAIL'}); Details=$env:OS },
        [pscustomobject]@{ Dependency='ScheduledTasks cmdlets'; Status=$(if ($MissingCmdlets.Count -eq 0) {'OK'} else {'FAIL'}); Details=$(if ($MissingCmdlets.Count -eq 0) {'Dostupni.'} else {"Nedostaju: $($MissingCmdlets -join ', ')"}) },
        [pscustomobject]@{ Dependency='.venv Python'; Status=$(if (Test-Path '.venv\Scripts\python.exe' -PathType Leaf) {'OK'} else {'FAIL'}); Details='Virtualno okruženje' },
        [pscustomobject]@{ Dependency='run-windows.ps1'; Status=$(if (Test-Path 'run-windows.ps1' -PathType Leaf) {'OK'} else {'FAIL'}); Details='Runtime skripta' },
        [pscustomobject]@{ Dependency='credentials.json'; Status=$(if (Test-Path 'credentials.json' -PathType Leaf) {'OK'} else {'FAIL'}); Details='Google Desktop OAuth' },
        [pscustomobject]@{ Dependency='OPENAI_API_KEY'; Status=$(if (Test-EnvValue 'OPENAI_API_KEY') {'OK'} else {'FAIL'}); Details='Vrijednost postoji; sadržaj se ne ispisuje.' }
    )
    $Checks | Format-Table -AutoSize | Out-Host
    if ($Checks.Status -contains 'FAIL') { Fail 'Scheduled Task nije registriran jer preflight nije prošao.' 'Dovršite setup, credentials.json i .env pa ponovno pokrenite ovu skriptu.' }

    $script:CurrentStep = 'Validacija PowerShell sintakse runtime skripte'
    $Tokens=$null; $ParseErrors=$null
    [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'run-windows.ps1'),[ref]$Tokens,[ref]$ParseErrors) | Out-Null
    if ($ParseErrors.Count -gt 0) { Fail "run-windows.ps1 ima sintaksnu pogrešku: $($ParseErrors[0].Message)" 'Vratite ispravnu verziju run-windows.ps1 prije registracije zadatka.' }

    $ScriptPath = Join-Path $PSScriptRoot 'run-windows.ps1'
    $PowerShell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path $PowerShell -PathType Leaf)) { Fail 'Windows PowerShell executable nije pronađen na očekivanoj putanji.' 'Provjerite Windows instalaciju i SystemRoot.' }
    $ActionArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Apply"
    $Action = New-ScheduledTaskAction -Execute $PowerShell -Argument $ActionArgs -WorkingDirectory $PSScriptRoot

    $Triggers = @()
    foreach ($Day in @('Monday','Tuesday','Wednesday','Thursday','Friday')) { $Triggers += New-ScheduledTaskTrigger -Weekly -DaysOfWeek $Day -At '07:30' }
    $Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -MultipleInstances IgnoreNew
    $CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $Principal = New-ScheduledTaskPrincipal -UserId $CurrentUser -LogonType Interactive -RunLevel Limited

    $script:CurrentStep = 'Registracija Scheduled Taska'
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Triggers -Settings $Settings -Principal $Principal -Description 'LangGraph Gmail obrada: nacrti i oznake, bez automatskog slanja.' -Force | Out-Null

    $script:CurrentStep = 'Provjera registriranog Scheduled Taska'
    $Registered = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    if (-not $Registered) { Fail "Task '$TaskName' nije moguće pročitati nakon registracije." 'Provjerite Task Scheduler i korisnička prava.' }

    Write-Host "Registriran i provjeren zadatak '$TaskName' za 07:30, ponedjeljak-petak." -ForegroundColor Green
}
catch {
    Write-Host "`nREGISTRACIJA NIJE USPJELA" -ForegroundColor Red
    Write-Host "FAILED STEP: $script:CurrentStep" -ForegroundColor Red
    Write-Host "CAUSE: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "HOW TO FIX: $script:Remediation" -ForegroundColor Yellow
    exit 1
}
