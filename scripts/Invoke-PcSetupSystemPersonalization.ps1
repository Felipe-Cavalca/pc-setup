#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Config,
    [Parameter(Mandatory)][string]$UserSid,
    [Parameter(Mandatory)][string]$ResultPath
)

$ErrorActionPreference = 'Stop'

function Write-PcSetupSystemResult {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Path)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $temporaryPath = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $temporaryPath -Encoding UTF8
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
    }
}

function ConvertTo-PcSetupTaskbarXml {
    param([Parameter(Mandatory)][hashtable]$Taskbar)

    $generation = [int]$Taskbar.PinGeneration
    $pins = @()
    foreach ($pin in @($Taskbar.Pins)) {
        $value = [Security.SecurityElement]::Escape([string]$pin.Value)
        $generationAttribute = " PinGeneration=`"$generation`""
        switch ([string]$pin.Type) {
            'AppUserModelID'             { $pins += "<taskbar:UWA AppUserModelID=`"$value`"$generationAttribute />" }
            'DesktopApplicationID'       { $pins += "<taskbar:DesktopApp DesktopApplicationID=`"$value`"$generationAttribute />" }
            'DesktopApplicationLinkPath' { $pins += "<taskbar:DesktopApp DesktopApplicationLinkPath=`"$value`"$generationAttribute />" }
            default { throw "Tipo de fixacao desconhecido: $($pin.Type)" }
        }
    }
    if ($pins.Count -eq 0) { $pins = @('<taskbar:DesktopApp DesktopApplicationLinkPath="#leaveempty" />') }
    $placement = if ($Taskbar.ReplaceDefaultPins) { ' PinListPlacement="Replace"' } else { '' }
    return ('<?xml version="1.0" encoding="utf-8"?>' +
        '<LayoutModificationTemplate xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification" xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout" xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout" xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout" Version="1">' +
        "<CustomTaskbarLayoutCollection$placement><defaultlayout:TaskbarLayout><taskbar:TaskbarPinList>" +
        ($pins -join '') +
        '</taskbar:TaskbarPinList></defaultlayout:TaskbarLayout></CustomTaskbarLayoutCollection></LayoutModificationTemplate>')
}

function Set-PcSetupDeviceCspInstance {
    param(
        [Parameter(Mandatory)][string]$ClassName,
        [Parameter(Mandatory)][string]$ParentId,
        [Parameter(Mandatory)][string]$InstanceId,
        [Parameter(Mandatory)][hashtable]$Properties
    )

    $namespace = 'root\cimv2\mdm\dmmap'
    $instance = Get-CimInstance -Namespace $namespace -ClassName $ClassName -Filter "ParentID='$ParentId' and InstanceID='$InstanceId'" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($instance) {
        foreach ($name in $Properties.Keys) { $instance.$name = $Properties[$name] }
        Set-CimInstance -CimInstance $instance -ErrorAction Stop | Out-Null
    }
    else {
        $values = @{ ParentID = $ParentId; InstanceID = $InstanceId }
        foreach ($name in $Properties.Keys) { $values[$name] = $Properties[$name] }
        New-CimInstance -Namespace $namespace -ClassName $ClassName -Property $values -ErrorAction Stop | Out-Null
    }

    $confirmed = Get-CimInstance -Namespace $namespace -ClassName $ClassName -Filter "ParentID='$ParentId' and InstanceID='$InstanceId'" -ErrorAction Stop | Select-Object -First 1
    if (-not $confirmed) { throw "O Windows nao retornou a instancia CSP $ClassName." }
    foreach ($name in $Properties.Keys) {
        if ([string]$confirmed.$name -ne [string]$Properties[$name]) { throw "O Windows nao confirmou $ClassName.$name." }
    }
}

function Set-PcSetupUserStartLayout {
    param(
        [Parameter(Mandatory)][string]$Sid,
        [Parameter(Mandatory)][string]$Xml
    )

    $namespace = 'root\cimv2\mdm\dmmap'
    $className = 'MDM_Policy_User_Config01_Start02'
    $options = New-Object Microsoft.Management.Infrastructure.Options.CimOperationOptions
    $options.SetCustomOption('PolicyPlatformContext_PrincipalContext_Type', 'PolicyPlatform_UserContext', $false)
    $options.SetCustomOption('PolicyPlatformContext_PrincipalContext_Id', $Sid, $false)
    $session = New-CimSession
    try {
        $lastError = $null
        foreach ($parentId in @('./User/Vendor/MSFT/Policy/Config', './Vendor/MSFT/Policy/Config')) {
            try {
                $key = New-Object Microsoft.Management.Infrastructure.CimInstance $className, $namespace
                $key.CimInstanceProperties.Add([Microsoft.Management.Infrastructure.CimProperty]::Create('ParentID', $parentId, 'String', 'Key'))
                $key.CimInstanceProperties.Add([Microsoft.Management.Infrastructure.CimProperty]::Create('InstanceID', 'Start', 'String', 'Key'))
                $existing = $null
                try { $existing = @($session.GetInstance($namespace, $key, $options))[0] }
                catch { }

                if ($existing) {
                    $existing.StartLayout = $Xml
                    $null = $session.ModifyInstance($namespace, $existing, $options)
                }
                else {
                    $key.CimInstanceProperties.Add([Microsoft.Management.Infrastructure.CimProperty]::Create('StartLayout', $Xml, 'String', 'Property'))
                    $null = $session.CreateInstance($namespace, $key, $options)
                }

                $confirmed = @($session.GetInstance($namespace, $key, $options))[0]
                if (-not $confirmed -or [string]$confirmed.StartLayout -ne $Xml) { throw 'O Windows nao confirmou o layout da barra de tarefas para a conta diaria.' }
                return
            }
            catch { $lastError = $_ }
        }
        throw "O CSP de usuario nao aceitou o layout da barra: $($lastError.Exception.Message)"
    }
    finally {
        if ($session) { $session.Dispose() }
    }
}

try {
    if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18') { throw 'Esta etapa deve ser executada como LocalSystem.' }
    Import-Module (Join-Path $PSScriptRoot 'lib\PcSetup.Core.psm1') -Force
    $configuration = Import-PcSetupConfiguration -Path $Config
    $personalization = $configuration.Personalization
    $allFolders = @('Documents','Downloads','FileExplorer','HomeGroup','Music','Network','PersonalFolder','Pictures','Settings','Videos')

    $startProperties = @{}
    foreach ($folder in $allFolders) {
        $startProperties["AllowPinnedFolder$folder"] = [int](@($personalization.StartPowerMenuFolders) -contains $folder)
    }
    Set-PcSetupDeviceCspInstance -ClassName 'MDM_Policy_Config01_Start02' -ParentId './Vendor/MSFT/Policy/Config' -InstanceId 'Start' -Properties $startProperties

    $taskbarXml = $null
    if ($personalization.Taskbar.Enabled) {
        $taskbarXml = ConvertTo-PcSetupTaskbarXml -Taskbar $personalization.Taskbar
        Set-PcSetupUserStartLayout -Sid $UserSid -Xml $taskbarXml
    }

    $result = [ordered]@{
        Status                = 'Completed'
        UserSid               = $UserSid
        StartPowerMenuFolders = @($personalization.StartPowerMenuFolders)
        TaskbarEnabled        = [bool]$personalization.Taskbar.Enabled
        TaskbarPinGeneration  = [int]$personalization.Taskbar.PinGeneration
        TaskbarPins           = @($personalization.Taskbar.Pins)
        CompletedAt           = (Get-Date).ToString('o')
    }
    Write-PcSetupSystemResult -Value $result -Path $ResultPath
    exit 0
}
catch {
    Write-PcSetupSystemResult -Value ([ordered]@{ Status = 'Failed'; Error = $_.Exception.Message; CompletedAt = (Get-Date).ToString('o') }) -Path $ResultPath
    exit 1
}
