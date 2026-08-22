#requires -RunAsAdministrator
$features = @(
    'Microsoft-Hyper-V-All',
    'Containers-DisposableClientVM',
    'VirtualMachinePlatform',
    'Microsoft-Windows-Subsystem-Linux'
)

foreach ($feature in $features) {
    $state = Get-WindowsOptionalFeature -Online -FeatureName $feature -ErrorAction Stop
    if ($state.State -eq 'Enabled') {
        Write-Host "[OK] $feature ja habilitado"
        continue
    }
    Write-Host "[ENABLE] $feature"
    Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart | Out-Null
}
