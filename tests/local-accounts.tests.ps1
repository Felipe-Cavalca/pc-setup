#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot

function Assert-Contains([string]$Content, [string]$Pattern, [string]$Message) {
    if ($Content -notmatch $Pattern) { throw $Message }
}

$users = Get-Content -LiteralPath (Join-Path $root 'scripts\30-users.ps1') -Raw
$verify = Get-Content -LiteralPath (Join-Path $root 'scripts\verify.ps1') -Raw
$orchestrator = Get-Content -LiteralPath (Join-Path $root 'scripts\Start-PcSetupUpdate.ps1') -Raw

Assert-Contains $users "Get-LocalGroup\s+-SID\s+'S-1-5-32-545'" 'A reconciliacao deve resolver o grupo Usuarios por SID.'
Assert-Contains $users 'AddToUsers' 'O plano deve informar a associacao ausente ao grupo Usuarios.'
Assert-Contains $users 'Add-LocalGroupMember\s+-Group\s+\$usersGroup\s+-Member\s+\$user' 'A aplicacao deve adicionar o objeto local exato ao grupo Usuarios.'
Assert-Contains $users 'Enable-LocalUser\s+-InputObject\s+\$user' 'Uma conta configurada existente deve ser habilitada.'
Assert-Contains $users 'Test-LocalAccountGroupMembership' 'A reconciliacao deve comparar membros por SID e permanecer idempotente.'

Assert-Contains $verify "Get-LocalGroup\s+-SID\s+'S-1-5-32-545'" 'O verify deve localizar o grupo Usuarios sem depender do idioma.'
Assert-Contains $verify 'Name "Logon \$\(\$account\.Name\)"' 'O verify deve emitir uma verificacao de logon por conta.'
Assert-Contains $verify '\$user\.Enabled' 'O verify deve falhar para uma conta configurada desabilitada.'
Assert-Contains $orchestrator 'Outro usuario com \.\\\$dailyUser' 'A troca de conta deve explicar o primeiro logon manual.'

Write-Host 'PASS: contas locais habilitadas e aptas ao primeiro logon.' -ForegroundColor Green
