$vmName = 'Publico'
$vmConnect = Join-Path $env:WINDIR 'System32\vmconnect.exe'
if (-not (Test-Path $vmConnect)) { throw 'VMConnect nao encontrado. Hyper-V esta instalado?' }
Start-Process -FilePath $vmConnect -ArgumentList @('localhost', $vmName)
