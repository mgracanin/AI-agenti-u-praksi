[CmdletBinding()]
param(
    [string]$TaskName = 'AI jutarnja obrada Gmaila'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Set-Location $PSScriptRoot

$script:CurrentStep = 'Pokretanje'
$script:Remediation = 'Provjerite prijavljeni preduvjet i ponovno pokrenite skriptu.'

function Fail {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $true)][string]$Fix
    )

    $script:Remediation = $Fix
    throw $Message
}

function Test-EnvValue {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not (Test-Path '.env' -PathType Leaf)) {
        return $false
    }

    $Prefix = $Name + '='
    $Line = Get-Content '.env' | Where-Object { $_ -like ($Prefix + '*') } | Select-Object -First 1
    if (-not $Line) {
        return $false
    }

    $Value = $Line.Substring($Prefix.Length).Trim()
    return (-not [string]::IsNullOrWhiteSpace($Value))
}

function New-DependencyCheck {
    param(
        [Parameter(Mandatory = $true)][string]$Dependency,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Details
    )

    $Status = 'FAIL'
    if ($Passed) {
        $Status = 'OK'
    }

    return [pscustomobject]@{
        Dependency = $Dependency
        Status     = $Status
        Details    = $Details
    }
}

try {
    $script:CurrentStep = 'Preflight i dependency report'

    $RequiredCmdlets = @(
        'New-ScheduledTaskAction'
        'New-ScheduledTaskTrigger'
        'New-ScheduledTaskSettingsSet'
        'New-ScheduledTaskPrincipal'
        'Register-ScheduledTask'
        'Get-ScheduledTask'
    )
    $MissingCmdlets = @($RequiredCmdlets | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })

    $ScheduledTasksDetails = 'Dostupni.'
    if ($MissingCmdlets.Count -gt 0) {
        $ScheduledTasksDetails = 'Nedostaju: ' + ($MissingCmdlets -join ', ')
    }

    $Checks = @(
        (New-DependencyCheck -Dependency 'Windows' -Passed ($env:OS -eq 'Windows_NT') -Details ([string]$env:OS))
        (New-DependencyCheck -Dependency 'ScheduledTasks cmdlets' -Passed ($MissingCmdlets.Count -eq 0) -Details $ScheduledTasksDetails)
        (New-DependencyCheck -Dependency '.venv Python' -Passed (Test-Path '.venv\Scripts\python.exe' -PathType Leaf) -Details 'Virtualno okruženje')
        (New-DependencyCheck -Dependency 'run-windows.ps1' -Passed (Test-Path 'run-windows.ps1' -PathType Leaf) -Details 'Runtime skripta')
        (New-DependencyCheck -Dependency 'credentials.json' -Passed (Test-Path 'credentials.json' -PathType Leaf) -Details 'Google Desktop OAuth')
        (New-DependencyCheck -Dependency 'OPENAI_API_KEY' -Passed (Test-EnvValue -Name 'OPENAI_API_KEY') -Details 'Vrijednost postoji; sadržaj se ne ispisuje.')
    )

    $Checks | Format-Table -AutoSize | Out-Host
    if ($Checks.Status -contains 'FAIL') {
        Fail -Message 'Scheduled Task nije registriran jer preflight nije prošao.' -Fix 'Dovršite setup, credentials.json i .env pa ponovno pokrenite ovu skriptu.'
    }

    $script:CurrentStep = 'Validacija PowerShell sintakse runtime skripte'
    $Tokens = $null
    $ParseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $PSScriptRoot 'run-windows.ps1'),
        [ref]$Tokens,
        [ref]$ParseErrors
    ) | Out-Null

    if ($ParseErrors.Count -gt 0) {
        $Message = 'run-windows.ps1 ima sintaksnu pogrešku: ' + $ParseErrors[0].Message
        Fail -Message $Message -Fix 'Vratite ispravnu verziju run-windows.ps1 prije registracije zadatka.'
    }

    $ScriptPath = Join-Path $PSScriptRoot 'run-windows.ps1'
    $PowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path $PowerShell -PathType Leaf)) {
        Fail -Message 'Windows PowerShell executable nije pronađen na očekivanoj putanji.' -Fix 'Provjerite Windows instalaciju i SystemRoot.'
    }

    $ActionArgs = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Apply' -f $ScriptPath
    $Action = New-ScheduledTaskAction -Execute $PowerShell -Argument $ActionArgs -WorkingDirectory $PSScriptRoot

    $Triggers = @()
    foreach ($Day in @('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday')) {
        $Triggers += New-ScheduledTaskTrigger -Weekly -DaysOfWeek $Day -At '07:30'
    }

    $Settings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 30) `
        -MultipleInstances IgnoreNew

    $CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $Principal = New-ScheduledTaskPrincipal -UserId $CurrentUser -LogonType Interactive -RunLevel Limited

    $script:CurrentStep = 'Registracija Scheduled Taska'
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $Action `
        -Trigger $Triggers `
        -Settings $Settings `
        -Principal $Principal `
        -Description 'LangGraph Gmail obrada: nacrti i oznake, bez automatskog slanja.' `
        -Force | Out-Null

    $script:CurrentStep = 'Provjera registriranog Scheduled Taska'
    $Registered = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    if (-not $Registered) {
        $Message = "Task '$TaskName' nije moguće pročitati nakon registracije."
        Fail -Message $Message -Fix 'Provjerite Task Scheduler i korisnička prava.'
    }

    Write-Host "Registriran i provjeren zadatak '$TaskName' za 07:30, ponedjeljak-petak." -ForegroundColor Green
}
catch {
    Write-Host "`nREGISTRACIJA NIJE USPJELA" -ForegroundColor Red
    Write-Host "FAILED STEP: $script:CurrentStep" -ForegroundColor Red
    Write-Host "CAUSE: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "HOW TO FIX: $script:Remediation" -ForegroundColor Yellow
    exit 1
}
