#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\lib\PcSetup.Recovery.psm1'
Import-Module $modulePath -Force

function Assert-Equal($Expected, $Actual, [string]$Message) {
    if ($Expected -ne $Actual) {
        throw "$Message Esperado: '$Expected'. Atual: '$Actual'."
    }
}

function Assert-True($Value, [string]$Message) {
    if (-not $Value) { throw $Message }
}

$state = @{ Count = 0; Points = @() }
$create = {
    param([string]$Description)
    $state.Count++
    $state.Points = @([pscustomobject]@{
        Description = $Description
        SequenceNumber = $state.Count
    })
}.GetNewClosure()
$list = { @($state.Points) }.GetNewClosure()

try {
    Stop-PcSetupChangeSession

    $session = Start-PcSetupChangeSession -EntryPoint 'bootstrap.ps1' -CreateAction $create -ListAction $list
    Assert-Equal 1 $state.Count 'A sessao deve criar exatamente um ponto.'
    Assert-Equal $false $session.Reused 'O primeiro ponto nao pode ser marcado como reutilizado.'
    Assert-True ($session.SessionId -match '^[a-f0-9]{32}$') 'A sessao deve receber um identificador persistivel.'

    $child = Enter-PcSetupProtectedScript -EntryPoint '10-windows-features.ps1' -CreateAction $create -ListAction $list
    Assert-Equal 1 $state.Count 'Um script interno nao deve criar outro ponto na mesma sessao.'
    Assert-Equal $true $child.Reused 'O script interno deve reutilizar o ponto validado.'

    $savedDescription = $session.Description
    $savedSequence = $session.SequenceNumber
    $savedSessionId = $session.SessionId
    Stop-PcSetupChangeSession
    $resumed = Resume-PcSetupChangeSession -Description $savedDescription -SequenceNumber $savedSequence -SessionId $savedSessionId -ListAction $list
    Assert-Equal 1 $state.Count 'A retomada nao deve criar um novo ponto.'
    Assert-Equal $true $resumed.Reused 'A retomada deve reutilizar apenas o ponto salvo para a aplicacao.'

    Stop-PcSetupChangeSession
    $direct = Enter-PcSetupProtectedScript -EntryPoint '20-directories.ps1' -CreateAction $create -ListAction $list
    Assert-Equal 2 $state.Count 'Um script executado diretamente deve criar seu proprio ponto.'
    Assert-Equal $false $direct.Reused 'O ponto da execucao direta nao pode ser reutilizado.'

    $creationFailed = $false
    try {
        Enter-PcSetupProtectedScript -EntryPoint '30-users.ps1' -CreateAction { param($Description) throw 'bloqueado' } -ListAction { @() } | Out-Null
    }
    catch {
        $creationFailed = $_.Exception.Message -match 'Nenhuma alteracao do pc-setup foi iniciada'
    }
    Assert-True $creationFailed 'Falha ao criar ponto deve interromper a execucao.'

    $validationFailed = $false
    try {
        Enter-PcSetupProtectedScript -EntryPoint '40-permissions.ps1' -CreateAction { param($Description) } -ListAction { @() } | Out-Null
    }
    catch {
        $validationFailed = $_.Exception.Message -match 'nao apareceu na validacao'
    }
    Assert-True $validationFailed 'Ponto ausente na validacao deve interromper a execucao.'

    $root = Split-Path -Parent $PSScriptRoot
    foreach ($relativePath in @(
        'scripts\05-machine.ps1',
        'scripts\10-windows-features.ps1',
        'scripts\20-directories.ps1',
        'scripts\30-users.ps1',
        'scripts\40-permissions.ps1',
        'scripts\50-debloat-akita.ps1',
        'scripts\70-wsl.ps1'
    )) {
        $content = Get-Content -Raw -LiteralPath (Join-Path $root $relativePath)
        Assert-True ($content -match 'Get-PcSetupExecutionMode') "$relativePath deve separar plano de aplicacao."
        Assert-True ($content -match 'Enter-PcSetupProtectedScript') "$relativePath deve exigir protecao de restauracao na aplicacao."
    }

    foreach ($relativePath in @('scripts\60-packages.ps1', 'scripts\80-personalization.ps1')) {
        $content = Get-Content -Raw -LiteralPath (Join-Path $root $relativePath)
        Assert-True ($content -match 'Get-PcSetupExecutionMode') "$relativePath deve separar plano de aplicacao."
        Assert-True ($content -match 'Assert-PcSetupCompletedApplyReport') "$relativePath deve exigir o comprovante da aplicacao Windows protegida."
        Assert-True ($content -notmatch 'Enter-PcSetupProtectedScript') "$relativePath nao deve criar outro ponto na fase sem elevacao da conta diaria."
    }
    $userPhase = Get-Content -Raw -LiteralPath (Join-Path $root 'scripts\90-user-profile.ps1')
    Assert-True ($userPhase -match 'Assert-PcSetupCompletedApplyReport') 'A fase da conta diaria deve validar o comprovante protegido antes de alterar o perfil.'

    Write-Host 'PASS: protecao obrigatoria de ponto de restauracao e comprovante da fase de usuario.' -ForegroundColor Green
}
finally {
    Stop-PcSetupChangeSession
}
