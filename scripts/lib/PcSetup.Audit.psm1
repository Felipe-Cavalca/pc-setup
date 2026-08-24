Set-StrictMode -Version 2.0

function New-PcSetupAuditRow {
    param([string]$Item, [string]$Status, [string]$Detail)
    return [pscustomobject][ordered]@{ Item = $Item; Status = $Status; Detalhe = $Detail }
}

function Get-PcSetupMachineAuditData {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Configuration)

    $collectionWarnings = @()
    $overview = @()
    $security = @()
    $virtualization = @()
    $storage = @()
    $devices = @()
    $setup = @()

    $overview += New-PcSetupAuditRow -Item 'Computador' -Status $env:COMPUTERNAME -Detail 'Nome atual do Windows'
    $overview += New-PcSetupAuditRow -Item 'Usuario atual' -Status $env:USERNAME -Detail 'Conta que gerou este relatorio'

    try {
        $computer = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $memoryGB = [math]::Round(([double]$computer.TotalPhysicalMemory / 1GB), 1)
        $overview += New-PcSetupAuditRow -Item 'Fabricante e modelo' -Status ([string]$computer.Manufacturer) -Detail ([string]$computer.Model)
        $overview += New-PcSetupAuditRow -Item 'Memoria' -Status "$memoryGB GB" -Detail 'Memoria fisica detectada'
    }
    catch { $collectionWarnings += "Computador: $($_.Exception.Message)" }

    try {
        $windows = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $version = if ([string]::IsNullOrWhiteSpace([string]$windows.DisplayVersion)) { [string]$windows.ReleaseId } else { [string]$windows.DisplayVersion }
        $productName = [string]$windows.ProductName
        if ([int]$windows.CurrentBuildNumber -ge 22000 -and $productName -match '^Windows 10') { $productName = $productName -replace '^Windows 10', 'Windows 11' }
        $overview += New-PcSetupAuditRow -Item 'Windows' -Status "$productName $version" -Detail "build $($windows.CurrentBuildNumber).$($windows.UBR)"
    }
    catch { $collectionWarnings += "Windows: $($_.Exception.Message)" }

    try {
        $processor = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $overview += New-PcSetupAuditRow -Item 'Processador' -Status ([string]$processor.Name).Trim() -Detail "$($processor.NumberOfCores) nucleos; $($processor.NumberOfLogicalProcessors) processadores logicos"
        $virtualization += New-PcSetupAuditRow -Item 'Virtualizacao no firmware' -Status $(if ($processor.VirtualizationFirmwareEnabled) { 'Habilitada' } else { 'Desabilitada ou indisponivel' }) -Detail 'Necessaria para Hyper-V e WSL 2'
        $virtualization += New-PcSetupAuditRow -Item 'SLAT' -Status $(if ($processor.SecondLevelAddressTranslationExtensions) { 'Disponivel' } else { 'Indisponivel' }) -Detail 'Traducao de enderecos de segundo nivel'
        $virtualization += New-PcSetupAuditRow -Item 'Extensoes de monitor de VM' -Status $(if ($processor.VMMonitorModeExtensions) { 'Disponiveis' } else { 'Indisponiveis' }) -Detail 'Capacidade do processador'
    }
    catch {
        if (-not [string]::IsNullOrWhiteSpace([string]$env:PROCESSOR_IDENTIFIER)) { $overview += New-PcSetupAuditRow -Item 'Processador' -Status ([string]$env:PROCESSOR_IDENTIFIER) -Detail 'Informacao resumida do ambiente' }
        $collectionWarnings += "Processador: $($_.Exception.Message)"
    }

    try {
        $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop
        $biosDate = if ($bios.ReleaseDate -is [datetime]) { $bios.ReleaseDate.ToString('yyyy-MM-dd') } else { [string]$bios.ReleaseDate }
        $overview += New-PcSetupAuditRow -Item 'BIOS/UEFI' -Status ([string]$bios.SMBIOSBIOSVersion) -Detail "fabricante=$($bios.Manufacturer); data=$biosDate"
    }
    catch { $collectionWarnings += "BIOS/UEFI: $($_.Exception.Message)" }

    try {
        $secureBoot = Confirm-SecureBootUEFI -ErrorAction Stop
        $security += New-PcSetupAuditRow -Item 'Secure Boot' -Status $(if ($secureBoot) { 'Habilitado' } else { 'Desabilitado' }) -Detail 'Estado informado pelo firmware'
    }
    catch { $security += New-PcSetupAuditRow -Item 'Secure Boot' -Status 'Indisponivel' -Detail $_.Exception.Message }

    try {
        $tpm = Get-Tpm -ErrorAction Stop
        $tpmProperties = @($tpm.PSObject.Properties.Name)
        if ($tpmProperties -contains 'TpmPresent') {
            $security += New-PcSetupAuditRow -Item 'TPM' -Status $(if ($tpm.TpmPresent) { 'Presente' } else { 'Ausente' }) -Detail "pronto=$($tpm.TpmReady); habilitado=$($tpm.TpmEnabled); ativado=$($tpm.TpmActivated)"
        }
        else { $security += New-PcSetupAuditRow -Item 'TPM' -Status 'Indisponivel' -Detail 'O Windows nao retornou o estado do TPM para esta conta.' }
    }
    catch { $security += New-PcSetupAuditRow -Item 'TPM' -Status 'Indisponivel' -Detail $_.Exception.Message }

    if ($Configuration.Security.ReportBitLockerStatus) {
        try {
            foreach ($volume in @(Get-BitLockerVolume -ErrorAction Stop)) {
                $security += New-PcSetupAuditRow -Item "BitLocker $($volume.MountPoint)" -Status ([string]$volume.ProtectionStatus) -Detail "volume=$($volume.VolumeStatus); metodo=$($volume.EncryptionMethod)"
            }
        }
        catch { $security += New-PcSetupAuditRow -Item 'BitLocker' -Status 'Indisponivel' -Detail $_.Exception.Message }
    }

    try {
        foreach ($disk in @(Get-PhysicalDisk -ErrorAction Stop | Sort-Object DeviceId)) {
            $details = @("tipo=$($disk.MediaType)", "barramento=$($disk.BusType)", "tamanho=$([math]::Round(([double]$disk.Size / 1GB), 1)) GB")
            try {
                $reliability = Get-StorageReliabilityCounter -PhysicalDisk $disk -ErrorAction Stop
                if ($null -ne $reliability.Temperature) { $details += "temperatura=$($reliability.Temperature) C" }
                if ($null -ne $reliability.Wear) { $details += "desgaste=$($reliability.Wear)%" }
                if ($null -ne $reliability.PowerOnHours) { $details += "horas=$($reliability.PowerOnHours)" }
                if ($null -ne $reliability.ReadErrorsTotal) { $details += "erros-leitura=$($reliability.ReadErrorsTotal)" }
                if ($null -ne $reliability.WriteErrorsTotal) { $details += "erros-gravacao=$($reliability.WriteErrorsTotal)" }
            }
            catch { $details += 'SMART detalhado indisponivel' }
            $storage += New-PcSetupAuditRow -Item ([string]$disk.FriendlyName) -Status "$($disk.HealthStatus) / $($disk.OperationalStatus)" -Detail ($details -join '; ')
        }
    }
    catch {
        foreach ($drive in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Where-Object Root)) {
            $sizeDetail = if ($null -ne $drive.Used -and $null -ne $drive.Free) { "usado=$([math]::Round(([double]$drive.Used / 1GB), 1)) GB; livre=$([math]::Round(([double]$drive.Free / 1GB), 1)) GB" } else { 'capacidade indisponivel' }
            $storage += New-PcSetupAuditRow -Item ([string]$drive.Root) -Status 'Volume acessivel; saude indisponivel' -Detail $sizeDetail
        }
        $collectionWarnings += "Armazenamento: $($_.Exception.Message)"
    }

    try {
        $problemDevices = @(Get-PnpDevice -PresentOnly -ErrorAction Stop | Where-Object Status -ne 'OK' | Sort-Object Class, FriendlyName)
        foreach ($device in @($problemDevices | Select-Object -First 50)) {
            $name = if ([string]::IsNullOrWhiteSpace([string]$device.FriendlyName)) { [string]$device.Class } else { [string]$device.FriendlyName }
            $devices += New-PcSetupAuditRow -Item $name -Status ([string]$device.Status) -Detail ([string]$device.Class)
        }
        if ($problemDevices.Count -eq 0) { $devices += New-PcSetupAuditRow -Item 'Dispositivos presentes' -Status 'OK' -Detail 'Nenhum dispositivo com erro foi encontrado' }
        if ($problemDevices.Count -gt 50) { $devices += New-PcSetupAuditRow -Item 'Lista limitada' -Status 'Aviso' -Detail "$($problemDevices.Count - 50) dispositivo(s) adicional(is) omitido(s)" }
    }
    catch { $devices += New-PcSetupAuditRow -Item 'Dispositivos' -Status 'Indisponivel' -Detail $_.Exception.Message }

    try {
        $systemRoot = [IO.Path]::GetPathRoot($env:SystemRoot)
        $reportDirectory = Get-PcSetupRuntimePath -Configuration $Configuration -Key 'ReportDirectory' -SystemRoot $systemRoot
        $verifyFile = Get-ChildItem -LiteralPath $reportDirectory -Filter 'verify-*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($verifyFile) {
            $verify = Get-Content -LiteralPath $verifyFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($status in @('PASS','WARN','FAIL')) {
                $count = @($verify.Checks | Where-Object Status -eq $status).Count
                $setup += New-PcSetupAuditRow -Item "Verificacao $status" -Status ([string]$count) -Detail $verifyFile.FullName
            }
        }
        else { $setup += New-PcSetupAuditRow -Item 'Verificacao do pc-setup' -Status 'Sem relatorio' -Detail 'Execute INSTALAR.cmd ou ATUALIZAR.cmd' }
    }
    catch { $setup += New-PcSetupAuditRow -Item 'Verificacao do pc-setup' -Status 'Indisponivel' -Detail $_.Exception.Message }

    try {
        $userReports = Get-PcSetupRuntimePath -Configuration $Configuration -Key 'UserReportDirectory'
        $restoreFile = Get-ChildItem -LiteralPath $userReports -Filter 'restore-test-*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($restoreFile) {
            $restore = Get-Content -LiteralPath $restoreFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $setup += New-PcSetupAuditRow -Item 'Teste de restauracao' -Status ([string]$restore.Status) -Detail "$($restore.Files) arquivo(s); $($restore.GeneratedAt)"
        }
        else { $setup += New-PcSetupAuditRow -Item 'Teste de restauracao' -Status 'Pendente' -Detail 'Execute TESTAR-RESTAURACAO.cmd depois de criar um backup' }
    }
    catch { $setup += New-PcSetupAuditRow -Item 'Teste de restauracao' -Status 'Indisponivel' -Detail $_.Exception.Message }

    try {
        $wslOutput = @(& wsl.exe --list --verbose 2>$null)
        if ($LASTEXITCODE -eq 0 -and $wslOutput.Count -gt 0) {
            $cleanWsl = @($wslOutput | ForEach-Object { ([string]$_).Replace([string][char]0, [string]::Empty).Trim() } | Where-Object { $_ })
            $setup += New-PcSetupAuditRow -Item 'WSL' -Status 'Detectado' -Detail ($cleanWsl -join ' | ')
        }
        else { $setup += New-PcSetupAuditRow -Item 'WSL' -Status 'Indisponivel' -Detail 'Nenhuma distribuicao foi listada' }
    }
    catch { $setup += New-PcSetupAuditRow -Item 'WSL' -Status 'Indisponivel' -Detail $_.Exception.Message }

    if ($collectionWarnings.Count -gt 0) {
        foreach ($warning in $collectionWarnings) { $setup += New-PcSetupAuditRow -Item 'Coleta parcial' -Status 'Aviso' -Detail $warning }
    }

    return [pscustomobject][ordered]@{
        SchemaVersion = '1.0'
        GeneratedAt   = (Get-Date).ToString('o')
        Profile       = [string]$Configuration.ProfileName
        Sections      = @(
            [pscustomobject]@{ Title = 'Visao geral'; Rows = @($overview) }
            [pscustomobject]@{ Title = 'Seguranca'; Rows = @($security) }
            [pscustomobject]@{ Title = 'Virtualizacao'; Rows = @($virtualization) }
            [pscustomobject]@{ Title = 'Armazenamento e saude'; Rows = @($storage) }
            [pscustomobject]@{ Title = 'Dispositivos com atencao'; Rows = @($devices) }
            [pscustomobject]@{ Title = 'Estado do pc-setup'; Rows = @($setup) }
        )
    }
}

function ConvertTo-PcSetupMarkdownValue {
    param($Value)
    if ($null -eq $Value) { return '' }
    return ([string]$Value).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
}

function ConvertTo-PcSetupMachineSummaryMarkdown {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Audit)

    $lines = @('# Resumo da maquina', '', "Gerado em: $($Audit.GeneratedAt)  ", "Perfil: $($Audit.Profile)", '')
    foreach ($section in @($Audit.Sections)) {
        $lines += "## $($section.Title)"
        $lines += ''
        $rows = @($section.Rows)
        if ($rows.Count -eq 0) {
            $lines += 'Informacao indisponivel.'
            $lines += ''
            continue
        }
        $properties = @($rows[0].PSObject.Properties.Name)
        $lines += '| ' + ($properties -join ' | ') + ' |'
        $lines += '| ' + (($properties | ForEach-Object { '---' }) -join ' | ') + ' |'
        foreach ($row in $rows) {
            $values = @($properties | ForEach-Object { ConvertTo-PcSetupMarkdownValue -Value $row.$_ })
            $lines += '| ' + ($values -join ' | ') + ' |'
        }
        $lines += ''
    }
    $lines += '> Este relatorio e informativo. Ele nao configura BitLocker, BIOS, firmware, TPM ou YubiKey.'
    return ($lines -join "`r`n") + "`r`n"
}

function ConvertTo-PcSetupMachineSummaryHtml {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Audit)

    $encode = { param($Value) [Net.WebUtility]::HtmlEncode([string]$Value) }
    $body = New-Object Text.StringBuilder
    foreach ($section in @($Audit.Sections)) {
        $null = $body.Append('<section><h2>').Append((& $encode $section.Title)).Append('</h2>')
        $rows = @($section.Rows)
        if ($rows.Count -eq 0) { $null = $body.Append('<p>Informacao indisponivel.</p></section>'); continue }
        $properties = @($rows[0].PSObject.Properties.Name)
        $null = $body.Append('<table><thead><tr>')
        foreach ($property in $properties) { $null = $body.Append('<th>').Append((& $encode $property)).Append('</th>') }
        $null = $body.Append('</tr></thead><tbody>')
        foreach ($row in $rows) {
            $null = $body.Append('<tr>')
            foreach ($property in $properties) { $null = $body.Append('<td>').Append((& $encode $row.$property)).Append('</td>') }
            $null = $body.Append('</tr>')
        }
        $null = $body.Append('</tbody></table></section>')
    }

    $generated = & $encode $Audit.GeneratedAt
    $profile = & $encode $Audit.Profile
    return @"
<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Resumo da maquina</title>
<style>body{font-family:Segoe UI,Arial,sans-serif;max-width:1100px;margin:32px auto;padding:0 20px;color:#172033;background:#f5f7fb}h1{margin-bottom:4px}h2{margin-top:0}header,section{background:#fff;border:1px solid #dbe2ea;border-radius:10px;padding:18px 20px;margin:16px 0;box-shadow:0 2px 8px #1720330d}table{width:100%;border-collapse:collapse}th,td{text-align:left;vertical-align:top;padding:9px;border-bottom:1px solid #e6ebf0}th{background:#eef3f8}footer{color:#52606d;margin:24px 0}</style>
</head><body><header><h1>Resumo da maquina</h1><p>Gerado em $generated<br>Perfil $profile</p></header>
$($body.ToString())
<footer>Relatorio informativo. Nao configura BitLocker, BIOS, firmware, TPM ou YubiKey.</footer></body></html>
"@
}

Export-ModuleMember -Function Get-PcSetupMachineAuditData, ConvertTo-PcSetupMachineSummaryMarkdown, ConvertTo-PcSetupMachineSummaryHtml
