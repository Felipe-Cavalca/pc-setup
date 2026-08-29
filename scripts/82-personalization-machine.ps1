#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Config = '',
    [string]$WindowsApplyReport = '',
    [switch]$CreateRestorePoint,
    [switch]$Plan,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Config)) { $Config = Join-Path (Split-Path -Parent $PSScriptRoot) 'config\machine.psd1' }
Import-Module (Join-Path $PSScriptRoot 'lib\PcSetup.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'lib\PcSetup.Recovery.psm1') -Force

function Get-PcSetupDailyUserSid {
    param([Parameter(Mandatory)][hashtable]$Configuration)
    $name = [string]$Configuration.Accounts.DailyUser.Name
    $user = Get-LocalUser -Name $name -ErrorAction Stop
    return [string]$user.SID.Value
}

function Remove-PcSetupMachineAppxPackages {
    param(
        [Parameter(Mandatory)][string[]]$Patterns,
        [Parameter(Mandatory)][string[]]$PreservePatterns
    )

    $removedInstalled = @()
    $removedProvisioned = @()
    $processedInstalled = @{}
    $processedProvisioned = @{}
    $isPreserved = {
        param([string]$Name, [string]$FullName)
        return @($PreservePatterns | Where-Object { $Name -like $_ -or $FullName -like $_ }).Count -gt 0
    }

    $installed = @(Get-AppxPackage -AllUsers -ErrorAction Stop)
    foreach ($pattern in $Patterns) {
        foreach ($package in @($installed | Where-Object { $_.Name -like $pattern -or $_.PackageFullName -like $pattern })) {
            if (& $isPreserved ([string]$package.Name) ([string]$package.PackageFullName)) { continue }
            if ($processedInstalled.ContainsKey([string]$package.PackageFullName)) { continue }
            Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
            $processedInstalled[[string]$package.PackageFullName] = $true
            $removedInstalled += [string]$package.Name
        }
    }

    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop)
    foreach ($pattern in $Patterns) {
        foreach ($package in @($provisioned | Where-Object { $_.DisplayName -like $pattern -or $_.PackageName -like $pattern })) {
            if (& $isPreserved ([string]$package.DisplayName) ([string]$package.PackageName)) { continue }
            if ($processedProvisioned.ContainsKey([string]$package.PackageName)) { continue }
            Remove-AppxProvisionedPackage -Online -PackageName $package.PackageName -AllUsers -ErrorAction Stop | Out-Null
            $processedProvisioned[[string]$package.PackageName] = $true
            $removedProvisioned += [string]$package.DisplayName
        }
    }

    $remainingInstalled = @(Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object {
        $package = $_
        @($Patterns | Where-Object { $package.Name -like $_ -or $package.PackageFullName -like $_ }).Count -gt 0 -and
        -not (& $isPreserved ([string]$package.Name) ([string]$package.PackageFullName))
    })
    $remainingProvisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | Where-Object {
        $package = $_
        @($Patterns | Where-Object { $package.DisplayName -like $_ -or $package.PackageName -like $_ }).Count -gt 0 -and
        -not (& $isPreserved ([string]$package.DisplayName) ([string]$package.PackageName))
    })
    if ($remainingInstalled.Count -gt 0 -or $remainingProvisioned.Count -gt 0) {
        throw "Ainda existem Appx configurados para remocao. Instalados: $($remainingInstalled.Count); provisionados: $($remainingProvisioned.Count)."
    }

    return [pscustomobject]@{
        Installed   = @($removedInstalled | Select-Object -Unique)
        Provisioned = @($removedProvisioned | Select-Object -Unique)
    }
}

function Invoke-PcSetupSystemPersonalization {
    param(
        [Parameter(Mandatory)][hashtable]$Configuration,
        [Parameter(Mandatory)][string]$ConfigPath,
        [Parameter(Mandatory)][string]$UserSid
    )

    $reportDirectory = Get-PcSetupRuntimePath -Configuration $Configuration -Key 'ReportDirectory' -SystemRoot ([IO.Path]::GetPathRoot($env:SystemRoot))
    $resultPath = Join-Path $reportDirectory ('personalization-system-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N') + '.json')
    $helperPath = Join-Path $PSScriptRoot 'Invoke-PcSetupSystemPersonalization.ps1'
    $taskName = 'pc-setup-personalization-' + [guid]::NewGuid().ToString('N')
    $powerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$helperPath`" -Config `"$ConfigPath`" -UserSid `"$UserSid`" -ResultPath `"$resultPath`""
    $action = New-ScheduledTaskAction -Execute $powerShell -Argument $arguments
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

    try {
        Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force | Out-Null
        Start-ScheduledTask -TaskName $taskName
        $deadline = (Get-Date).AddSeconds(90)
        do {
            Start-Sleep -Milliseconds 500
            $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
        } while (-not (Test-Path -LiteralPath $resultPath -PathType Leaf) -and (Get-Date) -lt $deadline)

        if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
            $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction Stop
            throw "A etapa LocalSystem nao produziu relatorio em 90 segundos. Estado: $($task.State); codigo: $($taskInfo.LastTaskResult)."
        }
        $result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($result.Status -ne 'Completed') { throw "A etapa LocalSystem falhou: $($result.Error)" }
        return [pscustomobject]@{ Path = $resultPath; Result = $result }
    }
    finally {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    }
}

$mode = Get-PcSetupExecutionMode -Plan:$Plan -Apply:$Apply
$configuration = Import-PcSetupConfiguration -Path $Config
$personalization = $configuration.Personalization

if (-not $personalization.Enabled) {
    Write-Host '[IGNORADO] Personalizacao de maquina desabilitada.'
    return [pscustomobject]@{ Step = 'PersonalizationMachine'; Mode = $mode; Enabled = $false; Action = 'None' }
}

if ($mode -eq 'Plan') {
    Write-Host "[PLANO] Mostrar no menu Iniciar somente: $(@($personalization.StartPowerMenuFolders) -join ', ')."
    if ($personalization.Taskbar.Enabled) {
        Write-Host "[PLANO] Tentar substituir os fixados padrao da barra por $(@($personalization.Taskbar.Pins).Count) item(ns), com PinGeneration=$($personalization.Taskbar.PinGeneration); se o CSP for recusado, manter ajuste manual."
    }
    if ($personalization.DisableEdgeBackground) { Write-Host '[PLANO] Desabilitar o inicio rapido e o modo em segundo plano do Edge por politica de maquina.' }
    if ($personalization.DisableWebSearch) { Write-Host "[PLANO] Desabilitar a pesquisa web no modo $($personalization.WebSearchMode)." }
    if (@($personalization.RemoveAppxPackages).Count -gt 0) { Write-Host '[PLANO] Remover os Appx configurados dos usuarios atuais e do provisionamento de novos perfis.' }
    return [pscustomobject]@{
        Step = 'PersonalizationMachine'; Mode = $mode; Enabled = $true
        StartPowerMenuFolders = @($personalization.StartPowerMenuFolders)
        Taskbar = $personalization.Taskbar
        EdgePolicies = [bool]$personalization.DisableEdgeBackground
        WebSearchPolicies = [bool]$personalization.DisableWebSearch
        WebSearchMode = [string]$personalization.WebSearchMode
        Action = 'Plan'
    }
}

Assert-PcSetupAdministrator
$sessionStarted = $false
try {
    if ($CreateRestorePoint) {
        $null = Start-PcSetupChangeSession -EntryPoint 'PERSONALIZAR.cmd'
        $sessionStarted = $true
    }
    else {
        if ([string]::IsNullOrWhiteSpace($WindowsApplyReport)) { throw 'A personalizacao automatica exige o relatorio protegido da fase Windows.' }
        $null = Assert-PcSetupCompletedApplyReport -Configuration $configuration -Path $WindowsApplyReport
    }

    $dailyUserSid = Get-PcSetupDailyUserSid -Configuration $configuration

    if ($personalization.DisableEdgeBackground) {
        $edgePolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
        if (-not (Test-Path -LiteralPath $edgePolicyPath)) { New-Item -Path $edgePolicyPath -Force | Out-Null }
        foreach ($edgePolicyName in @('StartupBoostEnabled', 'BackgroundModeEnabled')) {
            New-ItemProperty -LiteralPath $edgePolicyPath -Name $edgePolicyName -PropertyType DWord -Value 0 -Force | Out-Null
            if ([int](Get-ItemPropertyValue -LiteralPath $edgePolicyPath -Name $edgePolicyName -ErrorAction Stop) -ne 0) { throw "A politica $edgePolicyName do Edge nao foi confirmada." }
        }
    }

    $aggressiveWebSearch = 'NotRequested'
    if ($personalization.DisableWebSearch) {
        $searchPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
        if (-not (Test-Path -LiteralPath $searchPolicyPath)) { New-Item -Path $searchPolicyPath -Force | Out-Null }
        $searchPolicies = @{ DisableWebSearch = 1; ConnectedSearchUseWeb = 0; EnableDynamicContentInWSB = 0 }
        foreach ($searchPolicyName in $searchPolicies.Keys) {
            New-ItemProperty -LiteralPath $searchPolicyPath -Name $searchPolicyName -PropertyType DWord -Value $searchPolicies[$searchPolicyName] -Force | Out-Null
            if ([int](Get-ItemPropertyValue -LiteralPath $searchPolicyPath -Name $searchPolicyName -ErrorAction Stop) -ne $searchPolicies[$searchPolicyName]) { throw "A politica $searchPolicyName da pesquisa nao foi confirmada." }
        }

        if ($personalization.WebSearchMode -eq 'Aggressive') {
            $userPolicyPath = "Registry::HKEY_USERS\$dailyUserSid\Software\Policies\Microsoft\Windows\Explorer"
            if (Test-Path -LiteralPath "Registry::HKEY_USERS\$dailyUserSid") {
                if (-not (Test-Path -LiteralPath $userPolicyPath)) { New-Item -Path $userPolicyPath -Force | Out-Null }
                New-ItemProperty -LiteralPath $userPolicyPath -Name 'DisableSearchBoxSuggestions' -PropertyType DWord -Value 1 -Force | Out-Null
                if ([int](Get-ItemPropertyValue -LiteralPath $userPolicyPath -Name 'DisableSearchBoxSuggestions' -ErrorAction Stop) -ne 1) { throw 'O bloqueio agressivo da pesquisa web nao foi confirmado.' }
                $aggressiveWebSearch = 'Configured'
            }
            else {
                Write-Warning 'A conta diaria nao esta com o hive de Registro carregado; o bloqueio agressivo sera concluido quando PERSONALIZAR.cmd for executado nessa conta.'
                $aggressiveWebSearch = 'UserHiveUnavailable'
            }
        }
    }

    $appxResult = Remove-PcSetupMachineAppxPackages -Patterns @($personalization.RemoveAppxPackages) -PreservePatterns @($personalization.PreserveAppxPackages)
    $systemResult = Invoke-PcSetupSystemPersonalization -Configuration $configuration -ConfigPath $configuration._ConfigPath -UserSid $dailyUserSid
    if ($systemResult.Result.TaskbarStatus -eq 'ManualRequired') {
        Write-Warning "O Windows recusou o layout oficial da barra de tarefas. A instalacao continuara e a barra ficara para ajuste manual. Detalhe: $($systemResult.Result.TaskbarError)"
    }

    $result = [ordered]@{
        Step                   = 'PersonalizationMachine'
        Mode                   = $mode
        Enabled                = $true
        UserSid                = $dailyUserSid
        StartPowerMenuFolders  = @($personalization.StartPowerMenuFolders)
        Taskbar                = $personalization.Taskbar
        TaskbarStatus          = [string]$systemResult.Result.TaskbarStatus
        TaskbarError           = [string]$systemResult.Result.TaskbarError
        SystemCspReport        = $systemResult.Path
        EdgePolicies           = [bool]$personalization.DisableEdgeBackground
        WebSearchPolicies      = [bool]$personalization.DisableWebSearch
        WebSearchMode          = [string]$personalization.WebSearchMode
        AggressiveWebSearch    = $aggressiveWebSearch
        RemovedInstalledAppx   = @($appxResult.Installed)
        RemovedProvisionedAppx = @($appxResult.Provisioned)
        CompletedAt            = (Get-Date).ToString('o')
        Action                 = 'Completed'
    }
    $reportPath = Join-Path (Get-PcSetupRuntimePath -Configuration $configuration -Key 'ReportDirectory' -SystemRoot ([IO.Path]::GetPathRoot($env:SystemRoot))) ('personalization-machine-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
    Write-PcSetupJson -InputObject $result -Path $reportPath | Out-Null
    Write-Host "[RELATORIO] $reportPath" -ForegroundColor Green
    [pscustomobject]$result
}
finally {
    if ($sessionStarted) { Stop-PcSetupChangeSession }
}
