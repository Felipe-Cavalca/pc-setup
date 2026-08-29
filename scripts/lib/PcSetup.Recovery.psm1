Set-StrictMode -Version 2.0

$script:ContextActive = 'PC_SETUP_RESTORE_CONTEXT_ACTIVE'
$script:ContextDescription = 'PC_SETUP_RESTORE_CONTEXT_DESCRIPTION'
$script:ContextSequence = 'PC_SETUP_RESTORE_CONTEXT_SEQUENCE'
$script:ContextSessionId = 'PC_SETUP_RESTORE_CONTEXT_SESSION_ID'

function Get-PcSetupDefaultCreateAction {
    return {
        param([string]$Description)
        Checkpoint-Computer -Description $Description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    }
}

function Get-PcSetupDefaultListAction {
    return { @(Get-ComputerRestorePoint -ErrorAction Stop) }
}

function Get-PcSetupRestorePointDescription {
    param([Parameter(Mandatory)][string]$EntryPoint)

    $safeEntryPoint = [IO.Path]::GetFileName($EntryPoint) -replace '[^a-zA-Z0-9._-]', '_'
    return 'pc-setup antes de {0} {1}' -f $safeEntryPoint, (Get-Date -Format 'yyyyMMdd-HHmmss')
}

function New-PcSetupRequiredRestorePoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EntryPoint,
        [scriptblock]$CreateAction = (Get-PcSetupDefaultCreateAction),
        [scriptblock]$ListAction = (Get-PcSetupDefaultListAction)
    )

    $description = Get-PcSetupRestorePointDescription -EntryPoint $EntryPoint
    Write-Host "[RECOVERY] Criando ponto de restauracao: $description" -ForegroundColor Cyan

    try {
        & $CreateAction $description
    }
    catch {
        throw @"
Nao foi possivel criar o ponto de restauracao obrigatorio. Nenhuma alteracao do pc-setup foi iniciada.

Confirme que a Protecao do Sistema esta habilitada no volume do Windows e tente novamente.
O Windows tambem pode recusar um novo ponto quando outro foi criado nas ultimas 24 horas.

Detalhe: $($_.Exception.Message)
"@
    }

    try {
        $restorePoints = @(& $ListAction)
    }
    catch {
        throw "O Windows informou a criacao do ponto, mas ele nao pôde ser consultado. Execucao interrompida. Detalhe: $($_.Exception.Message)"
    }

    $created = $restorePoints |
        Where-Object { $_.Description -eq $description } |
        Sort-Object SequenceNumber -Descending |
        Select-Object -First 1

    if (-not $created) {
        throw 'O ponto de restauracao nao apareceu na validacao posterior. Execucao interrompida.'
    }

    Write-Host "[OK] Ponto de restauracao validado: $description" -ForegroundColor Green
    return [pscustomobject]@{
        Description    = $description
        SequenceNumber = [string]$created.SequenceNumber
        SessionId      = [guid]::NewGuid().ToString('N')
        Reused         = $false
    }
}

function Set-PcSetupRestoreContext {
    param(
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][string]$SequenceNumber,
        [Parameter(Mandatory)][string]$SessionId
    )

    [Environment]::SetEnvironmentVariable($script:ContextActive, '1', 'Process')
    [Environment]::SetEnvironmentVariable($script:ContextDescription, $Description, 'Process')
    [Environment]::SetEnvironmentVariable($script:ContextSequence, $SequenceNumber, 'Process')
    [Environment]::SetEnvironmentVariable($script:ContextSessionId, $SessionId, 'Process')
}

function Get-PcSetupActiveRestoreContext {
    [CmdletBinding()]
    param([scriptblock]$ListAction = (Get-PcSetupDefaultListAction))

    if ([Environment]::GetEnvironmentVariable($script:ContextActive, 'Process') -ne '1') {
        return $null
    }

    $description = [Environment]::GetEnvironmentVariable($script:ContextDescription, 'Process')
    $sequence = [Environment]::GetEnvironmentVariable($script:ContextSequence, 'Process')
    $sessionId = [Environment]::GetEnvironmentVariable($script:ContextSessionId, 'Process')
    if ([string]::IsNullOrWhiteSpace($description) -or [string]::IsNullOrWhiteSpace($sequence) -or [string]::IsNullOrWhiteSpace($sessionId)) {
        throw 'O contexto de restauracao da sessao esta incompleto. Execucao interrompida.'
    }

    $restorePoints = @(& $ListAction)
    $existing = $restorePoints |
        Where-Object { [string]$_.SequenceNumber -eq $sequence -and $_.Description -eq $description } |
        Select-Object -First 1

    if (-not $existing) {
        throw 'O ponto de restauracao da sessao nao pôde ser validado. Execucao interrompida.'
    }

    return [pscustomobject]@{
        Description    = $description
        SequenceNumber = $sequence
        SessionId      = $sessionId
        Reused         = $true
    }
}

function Start-PcSetupChangeSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EntryPoint,
        [scriptblock]$CreateAction = (Get-PcSetupDefaultCreateAction),
        [scriptblock]$ListAction = (Get-PcSetupDefaultListAction)
    )

    if ([Environment]::GetEnvironmentVariable($script:ContextActive, 'Process') -eq '1') {
        throw 'Ja existe uma sessao de alteracao pc-setup ativa neste processo.'
    }

    $restorePoint = New-PcSetupRequiredRestorePoint -EntryPoint $EntryPoint -CreateAction $CreateAction -ListAction $ListAction
    Set-PcSetupRestoreContext -Description $restorePoint.Description -SequenceNumber $restorePoint.SequenceNumber -SessionId $restorePoint.SessionId
    return $restorePoint
}

function Resume-PcSetupChangeSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][string]$SequenceNumber,
        [Parameter(Mandatory)][string]$SessionId,
        [switch]$ReturnNullIfMissing,
        [scriptblock]$ListAction = (Get-PcSetupDefaultListAction)
    )

    if ([Environment]::GetEnvironmentVariable($script:ContextActive, 'Process') -eq '1') {
        throw 'Ja existe uma sessao de alteracao pc-setup ativa neste processo.'
    }
    if ($SessionId -notmatch '^[a-fA-F0-9]{32}$') { throw 'Identificador da sessao de retomada invalido.' }

    $restorePoints = @(& $ListAction)
    $existing = $restorePoints |
        Where-Object { [string]$_.SequenceNumber -eq $SequenceNumber -and $_.Description -eq $Description } |
        Select-Object -First 1
    if (-not $existing) {
        if ($ReturnNullIfMissing) { return $null }
        throw 'O ponto de restauracao salvo para esta aplicacao nao existe mais. A retomada foi interrompida.'
    }

    Set-PcSetupRestoreContext -Description $Description -SequenceNumber $SequenceNumber -SessionId $SessionId
    Write-Host "[RECOVERY] Retomando a mesma aplicacao com o ponto validado: $Description" -ForegroundColor Cyan
    return [pscustomobject]@{
        Description    = $Description
        SequenceNumber = $SequenceNumber
        SessionId      = $SessionId
        Reused         = $true
    }
}

function Get-PcSetupChangeSessionContext {
    [CmdletBinding()]
    param([scriptblock]$ListAction = (Get-PcSetupDefaultListAction))

    return Get-PcSetupActiveRestoreContext -ListAction $ListAction
}

function Enter-PcSetupProtectedScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EntryPoint,
        [scriptblock]$CreateAction = (Get-PcSetupDefaultCreateAction),
        [scriptblock]$ListAction = (Get-PcSetupDefaultListAction)
    )

    $context = Get-PcSetupActiveRestoreContext -ListAction $ListAction
    if ($context) {
        Write-Host "[RECOVERY] Reutilizando ponto validado da sessao: $($context.Description)" -ForegroundColor DarkGray
        return $context
    }

    return New-PcSetupRequiredRestorePoint -EntryPoint $EntryPoint -CreateAction $CreateAction -ListAction $ListAction
}

function Stop-PcSetupChangeSession {
    [CmdletBinding()]
    param()

    foreach ($name in @($script:ContextActive, $script:ContextDescription, $script:ContextSequence, $script:ContextSessionId)) {
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
}

Export-ModuleMember -Function Start-PcSetupChangeSession, Resume-PcSetupChangeSession, Get-PcSetupChangeSessionContext, Enter-PcSetupProtectedScript, Stop-PcSetupChangeSession
