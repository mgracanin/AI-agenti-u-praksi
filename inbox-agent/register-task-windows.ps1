[CmdletBinding()]
param(
    [string]$TaskName = 'AI jutarnja obrada Gmaila'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Set-Location $PSScriptRoot

if (-not (Test-Path '.venv\Scripts\python.exe')) {
    throw 'Prvo pokrenite setup-windows.ps1.'
}
if (-not (Test-Path 'credentials.json')) {
    throw 'Prvo dodajte credentials.json i ručno dovršite dry-run.'
}

$ScriptPath = Join-Path $PSScriptRoot 'run-windows.ps1'
$PowerShell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$ActionArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Apply"
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

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Triggers `
    -Settings $Settings `
    -Principal $Principal `
    -Description 'LangGraph Gmail obrada: nacrti i oznake, bez automatskog slanja.' `
    -Force | Out-Null

Write-Host "Registriran je zadatak '$TaskName' za 07:30, ponedjeljak-petak." -ForegroundColor Green
Write-Host "Provjera: Get-ScheduledTask -TaskName '$TaskName'"
