Set-StrictMode -Version 2.0

function ConvertTo-PcSetupPlanValue {
    param($Value, [int]$Depth = 0)

    if ($null -eq $Value) { return '' }
    if ($Value -is [bool]) { return $(if ($Value) { 'Sim' } else { 'Nao' }) }
    if ($Value -is [string] -or $Value -is [char] -or $Value -is [ValueType]) { return [string]$Value }
    if ($Depth -ge 3) { return [string]$Value }

    if ($Value -is [System.Collections.IDictionary]) {
        $pairs = foreach ($key in @($Value.Keys | Sort-Object)) {
            "$key=$(ConvertTo-PcSetupPlanValue -Value $Value[$key] -Depth ($Depth + 1))"
        }
        return $pairs -join ', '
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        $items = foreach ($item in @($Value)) { ConvertTo-PcSetupPlanValue -Value $item -Depth ($Depth + 1) }
        return $items -join '; '
    }

    $properties = @($Value.PSObject.Properties | Where-Object MemberType -in @('NoteProperty', 'Property'))
    if ($properties.Count -gt 0) {
        $pairs = foreach ($property in $properties) {
            "$($property.Name)=$(ConvertTo-PcSetupPlanValue -Value $property.Value -Depth ($Depth + 1))"
        }
        return $pairs -join ', '
    }

    return [string]$Value
}

function ConvertTo-PcSetupPlanAction {
    param([string]$Value)

    $translations = @{
        Configure       = 'Configurar'
        Create          = 'Criar'
        Enable          = 'Habilitar'
        InstallOrUpdate = 'Instalar ou atualizar'
        None            = 'Sem alteracao'
        Planned         = 'Planejado'
        Rename          = 'Renomear'
    }
    if ($translations.ContainsKey($Value)) { return $translations[$Value] }
    if ([string]::IsNullOrWhiteSpace($Value)) { return 'Planejado' }
    return $Value
}

function Get-PcSetupPlanSummaryRows {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Plan)

    $rows = @()
    foreach ($step in @($Plan.Steps)) {
        $stepName = if ([string]::IsNullOrWhiteSpace([string]$step.Step)) { 'Etapa' } else { [string]$step.Step }
        $items = @()
        if ($step.PSObject.Properties.Name -contains 'Items') { $items = @($step.Items) }
        if ($items.Count -eq 0) { $items = @($step) }

        $sequence = 0
        foreach ($item in $items) {
            $sequence++
            if ($item -is [string]) {
                $rows += [pscustomobject][ordered]@{ Etapa = $stepName; Item = [string]$item; Acao = 'Planejado'; Detalhes = '' }
                continue
            }

            $propertyNames = @($item.PSObject.Properties.Name)
            $identityProperty = @('PackageId', 'Name', 'Key', 'Path', 'Step') | Where-Object { $propertyNames -contains $_ } | Select-Object -First 1
            $actionProperty = @('Action', 'Status') | Where-Object { $propertyNames -contains $_ } | Select-Object -First 1
            $identity = if ($identityProperty) { [string]$item.$identityProperty } else { "Item $sequence" }
            $action = if ($actionProperty) { ConvertTo-PcSetupPlanAction -Value ([string]$item.$actionProperty) } else { 'Planejado' }
            $excluded = @('Step', 'Mode', 'Items', $identityProperty, $actionProperty) | Where-Object { $_ }
            $details = foreach ($property in @($item.PSObject.Properties)) {
                if ($property.Name -notin $excluded) {
                    "$($property.Name)=$(ConvertTo-PcSetupPlanValue -Value $property.Value)"
                }
            }
            $rows += [pscustomobject][ordered]@{ Etapa = $stepName; Item = $identity; Acao = $action; Detalhes = ($details -join '; ') }
        }
    }
    return $rows
}

function ConvertTo-PcSetupPlanMarkdownValue {
    param($Value)
    if ($null -eq $Value) { return '' }
    return ([string]$Value).Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ')
}

function ConvertTo-PcSetupPlanSummaryMarkdown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)][string]$JsonPath
    )

    $lines = @(
        '# Plano do pc-setup',
        '',
        '> **PREVIA:** este documento descreve o que o pc-setup pretende fazer. Nenhuma alteracao foi aplicada nesta etapa.',
        '',
        "Gerado em: $($Plan.CompletedAt)  ",
        "Perfil: $($Plan.Profile)  ",
        "Windows: $($Plan.Windows.ProductName) $($Plan.Windows.DisplayVersion), build $($Plan.Windows.Build)  ",
        "Sistema: $($Plan.Storage.SystemRoot)  ",
        "Dados: $($Plan.Storage.DataRoot) ($($Plan.Storage.DataMode))  ",
        "Plano tecnico JSON: $JsonPath",
        '',
        '## Etapas planejadas',
        '',
        '| Etapa | Item | Acao | Detalhes |',
        '| --- | --- | --- | --- |'
    )
    foreach ($row in @(Get-PcSetupPlanSummaryRows -Plan $Plan)) {
        $values = @('Etapa', 'Item', 'Acao', 'Detalhes') | ForEach-Object { ConvertTo-PcSetupPlanMarkdownValue -Value $row.$_ }
        $lines += '| ' + ($values -join ' | ') + ' |'
    }
    $lines += ''
    $lines += '> A aplicacao so pode continuar se a configuracao, os scripts e a escolha de armazenamento ainda coincidirem com este plano.'
    return ($lines -join "`r`n") + "`r`n"
}

function ConvertTo-PcSetupPlanSummaryHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)][string]$JsonPath
    )

    $encode = { param($Value) [Net.WebUtility]::HtmlEncode([string]$Value) }
    $rows = New-Object Text.StringBuilder
    foreach ($row in @(Get-PcSetupPlanSummaryRows -Plan $Plan)) {
        $null = $rows.Append('<tr>')
        foreach ($property in @('Etapa', 'Item', 'Acao', 'Detalhes')) {
            $null = $rows.Append('<td>').Append((& $encode $row.$property)).Append('</td>')
        }
        $null = $rows.Append('</tr>')
    }

    $generated = & $encode $Plan.CompletedAt
    $profile = & $encode $Plan.Profile
    $windows = & $encode "$($Plan.Windows.ProductName) $($Plan.Windows.DisplayVersion), build $($Plan.Windows.Build)"
    $systemRoot = & $encode $Plan.Storage.SystemRoot
    $dataRoot = & $encode "$($Plan.Storage.DataRoot) ($($Plan.Storage.DataMode))"
    $json = & $encode $JsonPath
    return @"
<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Plano do pc-setup</title>
<style>body{font-family:Segoe UI,Arial,sans-serif;max-width:1200px;margin:32px auto;padding:0 20px;color:#172033;background:#f5f7fb}header,main{background:#fff;border:1px solid #dbe2ea;border-radius:10px;padding:18px 20px;margin:16px 0;box-shadow:0 2px 8px #1720330d}.warning{background:#fff4ce;border:1px solid #e6b800;border-radius:8px;padding:12px 14px;font-weight:600}table{width:100%;border-collapse:collapse}th,td{text-align:left;vertical-align:top;padding:9px;border-bottom:1px solid #e6ebf0}th{background:#eef3f8}footer{color:#52606d;margin:24px 0}code{overflow-wrap:anywhere}</style>
</head><body><header><h1>Plano do pc-setup</h1><p class="warning">PREVIA: nenhuma alteracao foi aplicada nesta etapa.</p><p>Gerado em $generated<br>Perfil: $profile<br>Windows: $windows<br>Sistema: $systemRoot<br>Dados: $dataRoot<br>Plano tecnico JSON: <code>$json</code></p></header>
<main><h2>Etapas planejadas</h2><table><thead><tr><th>Etapa</th><th>Item</th><th>Acao</th><th>Detalhes</th></tr></thead><tbody>$($rows.ToString())</tbody></table></main>
<footer>A aplicacao so pode continuar se a configuracao, os scripts e a escolha de armazenamento ainda coincidirem com este plano.</footer></body></html>
"@
}

function Write-PcSetupPlanSummaryFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)][string]$JsonPath,
        [Parameter(Mandatory)][string]$OutputDirectory,
        [Parameter(Mandatory)][string]$FileBaseName,
        [Parameter(Mandatory)][object[]]$Formats
    )

    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    $written = @()
    foreach ($format in @($Formats)) {
        if ([string]$format -eq 'Html') {
            $path = Join-Path $OutputDirectory ($FileBaseName + '.html')
            ConvertTo-PcSetupPlanSummaryHtml -Plan $Plan -JsonPath $JsonPath | Set-Content -LiteralPath $path -Encoding UTF8
            $written += $path
        }
        elseif ([string]$format -eq 'Markdown') {
            $path = Join-Path $OutputDirectory ($FileBaseName + '.md')
            ConvertTo-PcSetupPlanSummaryMarkdown -Plan $Plan -JsonPath $JsonPath | Set-Content -LiteralPath $path -Encoding UTF8
            $written += $path
        }
    }
    return [pscustomobject]@{ Status = 'Completed'; Files = @($written); JsonReport = $JsonPath }
}

Export-ModuleMember -Function Get-PcSetupPlanSummaryRows, ConvertTo-PcSetupPlanSummaryMarkdown, ConvertTo-PcSetupPlanSummaryHtml, Write-PcSetupPlanSummaryFiles
