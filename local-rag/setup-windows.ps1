[CmdletBinding()]
param([switch]$Gpu)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Set-Location $PSScriptRoot

$script:CurrentStep = 'Pokretanje'
$script:Remediation = 'Provjerite prijavljeni problem i ponovno pokrenite skriptu.'

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }
function Fail([string]$Message, [string]$Fix) { $script:Remediation = $Fix; throw $Message }
function Add-Check([System.Collections.ArrayList]$List, [string]$Dependency, [bool]$Ok, [string]$Details) {
    [void]$List.Add([pscustomobject]@{ Dependency=$Dependency; Status=$(if ($Ok) {'OK'} else {'FAIL'}); Details=$Details })
}
function Assert-PowerShellSyntax([string[]]$Paths) {
    foreach ($Path in $Paths) {
        $FullPath = Join-Path $PSScriptRoot $Path
        if (-not (Test-Path $FullPath -PathType Leaf)) { Fail "Nedostaje $Path." 'Ponovno preuzmite cijeli local-rag direktorij.' }
        $Tokens=$null; $ParseErrors=$null
        [System.Management.Automation.Language.Parser]::ParseFile($FullPath,[ref]$Tokens,[ref]$ParseErrors) | Out-Null
        if ($ParseErrors.Count -gt 0) { Fail "PowerShell sintaksa nije valjana u ${Path}: $($ParseErrors[0].Message)" 'Vratite izvornu verziju skripte ili ispravite prijavljenu sintaksnu pogrešku.' }
    }
}
function New-HexSecret {
    $Bytes = New-Object byte[] 32
    $Rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $Rng.GetBytes($Bytes) } finally { $Rng.Dispose() }
    return ([BitConverter]::ToString($Bytes)).Replace('-','').ToLowerInvariant()
}
function Test-ComposeOwnsPort([string]$Service, [int]$ContainerPort, [int]$HostPort) {
    $Ids = @(& docker.exe compose ps --status running -q $Service 2>$null)
    if ($LASTEXITCODE -ne 0 -or $Ids.Count -eq 0 -or [string]::IsNullOrWhiteSpace(($Ids -join ''))) { return $false }
    $Mappings = @(& docker.exe compose port $Service $ContainerPort 2>$null)
    if ($LASTEXITCODE -ne 0) { return $false }
    foreach ($Mapping in $Mappings) {
        if ($Mapping -match "(^|:)$HostPort$") { return $true }
    }
    return $false
}
function Get-PortOwnerDescription([int]$Port) {
    $Listeners = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
    if ($Listeners.Count -eq 0) { return 'nema aktivnog TCP listenera' }
    $Descriptions = foreach ($Listener in $Listeners) {
        $PidValue = $Listener.OwningProcess
        $Process = Get-Process -Id $PidValue -ErrorAction SilentlyContinue
        if ($Process) {
            $Path = $null
            try { $Path = $Process.Path } catch { $Path = $null }
            if ($Path) { "PID $PidValue ($($Process.ProcessName), $Path)" } else { "PID $PidValue ($($Process.ProcessName))" }
        } else { "PID $PidValue" }
    }
    return ($Descriptions -join '; ')
}

try {
    $script:CurrentStep = 'Preflight i dependency report'
    $Checks = [System.Collections.ArrayList]::new()
    $IsWindows = ($env:OS -eq 'Windows_NT')
    Add-Check $Checks 'Windows 11' $IsWindows $(if ($IsWindows) {[Environment]::OSVersion.VersionString} else {'Skripta se ne izvodi na Windowsu.'})

    $Docker = Get-Command docker.exe -ErrorAction SilentlyContinue
    Add-Check $Checks 'Docker CLI' ($null -ne $Docker) $(if ($Docker) {$Docker.Source} else {'docker.exe nije u PATH-u.'})

    $NetTcp = Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue
    Add-Check $Checks 'Get-NetTCPConnection' ($null -ne $NetTcp) $(if ($NetTcp) {'NetTCPIP modul dostupan.'} else {'NetTCPIP cmdlet nije pronađen.'})

    $RequiredFiles = @('compose.yaml','.env.example','verify-windows.ps1')
    if ($Gpu) { $RequiredFiles += 'compose.gpu.yaml' }
    foreach ($File in $RequiredFiles) {
        Add-Check $Checks $File (Test-Path $File -PathType Leaf) $(if (Test-Path $File -PathType Leaf) {'Pronađen.'} else {'Nedostaje.'})
    }

    $DockerEngineOk = $false
    $ComposeOk = $false
    if ($Docker) {
        & docker.exe info *> $null
        $DockerEngineOk = ($LASTEXITCODE -eq 0)
        & docker.exe compose version *> $null
        $ComposeOk = ($LASTEXITCODE -eq 0)
    }
    Add-Check $Checks 'Docker Linux engine' $DockerEngineOk $(if ($DockerEngineOk) {'Dostupan.'} else {'Docker Desktop nije pokrenut ili Linux engine nije spreman.'})
    Add-Check $Checks 'Docker Compose v2' $ComposeOk $(if ($ComposeOk) {'Dostupan.'} else {'docker compose nije dostupan.'})

    if ($Gpu) {
        $Nvidia = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
        $Wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
        $WslOk = $false
        if ($Wsl) {
            & wsl.exe --status *> $null
            $WslOk = ($LASTEXITCODE -eq 0)
        }
        Add-Check $Checks 'NVIDIA driver / nvidia-smi' ($null -ne $Nvidia) $(if ($Nvidia) {$Nvidia.Source} else {'nvidia-smi.exe nije pronađen.'})
        Add-Check $Checks 'WSL 2' $WslOk $(if ($WslOk) {'Spreman.'} else {'WSL 2 nije spreman.'})
    }

    $Checks | Format-Table -AutoSize | Out-Host
    if (-not $IsWindows) { Fail 'Ova je skripta namijenjena Windowsu 11.' 'Pokrenite je u Windows PowerShellu na Windowsu 11.' }
    if (-not $Docker) { Fail 'Docker CLI nije pronađen.' 'Instalirajte Docker Desktop, uključite WSL 2 backend i ponovno otvorite PowerShell.' }
    if ($Checks.Status -contains 'FAIL') { Fail 'Jedan ili više preduvjeta nisu zadovoljeni.' 'Ispravite sve stavke označene s FAIL i ponovno pokrenite setup.' }

    Assert-PowerShellSyntax @('setup-windows.ps1','verify-windows.ps1')

    if ($PSScriptRoot -match 'OneDrive') { Write-Warning 'Projekt je u OneDrive putanji. Premjestite ga, primjerice, u C:\AI\local-rag zbog pouzdanijih bind mountova.' }

    Write-Step 'Provjera TCP portova'
    $script:CurrentStep = 'Provjera portova'
    $PortMap = @(
        [pscustomobject]@{ Port=5678; Service='n8n'; ContainerPort=5678 },
        [pscustomobject]@{ Port=6333; Service='qdrant'; ContainerPort=6333 },
        [pscustomobject]@{ Port=11434; Service='ollama'; ContainerPort=11434 }
    )
    foreach ($Item in $PortMap) {
        $Listener = Get-NetTCPConnection -State Listen -LocalPort $Item.Port -ErrorAction SilentlyContinue
        if ($Listener) {
            if (Test-ComposeOwnsPort $Item.Service $Item.ContainerPort $Item.Port) {
                Write-Host "TCP port $($Item.Port): već ga koristi očekivani Compose servis '$($Item.Service)'." -ForegroundColor Green
            } else {
                $Owner = Get-PortOwnerDescription $Item.Port
                Fail "TCP port $($Item.Port) već koristi drugi proces: $Owner" "Zaustavite proces koji sluša na portu $($Item.Port), promijenite mapiranje porta u compose.yaml ili uklonite drugi servis koji ga koristi."
            }
        } else {
            Write-Host "TCP port $($Item.Port): slobodan." -ForegroundColor Green
        }
    }

    New-Item -ItemType Directory -Path 'documents' -Force | Out-Null
    if (-not (Test-Path '.env' -PathType Leaf)) {
        $script:CurrentStep = 'Generiranje .env konfiguracije'
        $EnvText = Get-Content '.env.example' -Raw
        $EnvText = $EnvText.Replace('zamijenite_dugim_nasumicnim_kljucem',(New-HexSecret))
        $EnvText = $EnvText.Replace('zamijenite_drugim_dugim_nasumicnim_kljucem',(New-HexSecret))
        [IO.File]::WriteAllText((Join-Path $PSScriptRoot '.env'),$EnvText,[Text.UTF8Encoding]::new($false))
        Write-Host 'Napravljen je .env s dva različita kriptografski nasumična ključa.' -ForegroundColor Green
    }
    $CurrentEnv = Get-Content '.env' -Raw
    if ($CurrentEnv -match 'zamijenite_') { Fail '.env još sadrži predložene vrijednosti.' 'Obrišite .env i ponovno pokrenite skriptu ili ručno postavite sve ključeve.' }

    $ComposeArgs = @('compose')
    if ($Gpu) { $ComposeArgs += @('-f','compose.yaml','-f','compose.gpu.yaml') }

    Write-Step 'Provjera Compose konfiguracije'
    $script:CurrentStep = 'docker compose config'
    & docker.exe @ComposeArgs config -q
    if ($LASTEXITCODE -ne 0) { Fail 'Compose konfiguracija nije valjana.' 'Pokrenite docker compose config bez -q i ispravite prijavljeni YAML ili .env problem.' }

    Write-Step 'Pokretanje n8n, Ollame i Qdranta'
    $script:CurrentStep = 'docker compose up'
    & docker.exe @ComposeArgs up -d
    if ($LASTEXITCODE -ne 0) { Fail 'Pokretanje kontejnera nije uspjelo.' 'Pokrenite docker compose ps i docker compose logs, ispravite prijavljeni problem i ponovno pokrenite setup.' }

    Write-Step 'Preuzimanje lokalnih modela'
    $script:CurrentStep = 'Preuzimanje qwen3:8b'
    & docker.exe @ComposeArgs exec -T ollama ollama pull qwen3:8b
    if ($LASTEXITCODE -ne 0) { Fail 'Preuzimanje qwen3:8b nije uspjelo.' 'Provjerite internetsku vezu i docker compose logs ollama. Stack ostaje pokrenut radi dijagnostike.' }
    $script:CurrentStep = 'Preuzimanje qwen3-embedding:0.6b'
    & docker.exe @ComposeArgs exec -T ollama ollama pull qwen3-embedding:0.6b
    if ($LASTEXITCODE -ne 0) { Fail 'Preuzimanje embedding modela nije uspjelo.' 'Provjerite internetsku vezu i docker compose logs ollama. Stack ostaje pokrenut radi dijagnostike.' }

    Write-Host "`nStack je pokrenut i setup faze su prošle." -ForegroundColor Green
    Write-Host '1. Pokrenite .\verify-windows.ps1'
    Write-Host '2. Otvorite http://localhost:5678'
    Write-Host '3. Uvezite rag-01-ingest.json i rag-02-chat.json'
}
catch {
    Write-Host "`nLOCAL-RAG SETUP NIJE DOVRŠEN" -ForegroundColor Red
    Write-Host "FAILED STEP: $script:CurrentStep" -ForegroundColor Red
    Write-Host "CAUSE: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "HOW TO FIX: $script:Remediation" -ForegroundColor Yellow
    Write-Host 'Dijagnostika: docker compose ps; docker compose logs --tail 100' -ForegroundColor Yellow
    exit 1
}
