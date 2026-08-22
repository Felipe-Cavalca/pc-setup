#requires -RunAsAdministrator
if (-not (Test-Path 'D:\Dev')) { throw 'Execute 20-directories.ps1 antes.' }

$computer = $env:COMPUTERNAME

function Reset-Acl([string]$Path, [string[]]$Grants) {
    & icacls $Path /inheritance:r | Out-Null
    & icacls $Path /grant:r 'SYSTEM:(OI)(CI)F' 'Administrators:(OI)(CI)F' | Out-Null
    foreach ($grant in $Grants) { & icacls $Path /grant $grant | Out-Null }
}

Reset-Acl 'D:\Dev' @("${computer}\Felipe:(OI)(CI)M", "${computer}\Codex:(OI)(CI)M")
Reset-Acl 'D:\Data\Felipe' @("${computer}\Felipe:(OI)(CI)F")
Reset-Acl 'D:\Agent\Codex' @("${computer}\Codex:(OI)(CI)F")

Write-Host '[OK] ACLs principais aplicadas.'
Write-Warning 'Nao aplique ACLs recursivas improvisadas em C:\Windows, C:\Program Files ou D:\VMs.'
