Set-StrictMode -Version 2.0

$script:SensitiveNamePattern = '(?i)(password|passwd|secret|token|credential|authorization|api[-_]?key|private[-_]?key|recovery[-_]?key|(^|[-_])pin($|[-_]))'

function Protect-PcSetupLogText {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return $null }
    $text = [string]$Value
    $text = [regex]::Replace(
        $text,
        '(?i)((?:password|passwd|secret|token|credential|authorization|api[-_]?key|private[-_]?key|recovery[-_]?key|pin)\s*[:=]\s*)(?:"[^"]*"|''[^'']*''|[^\s,;]+)',
        '$1[REDACTED]'
    )
    return [regex]::Replace($text, '(?i)(://[^:/\s]+:)[^@\s]+@', '$1[REDACTED]@')
}

function Protect-PcSetupLogData {
    param(
        [AllowNull()][object]$Value,
        [string]$Name = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($Name) -and $Name -match $script:SensitiveNamePattern) { return '[REDACTED]' }
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        $protected = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $protected[[string]$key] = Protect-PcSetupLogData -Value $Value[$key] -Name ([string]$key)
        }
        return $protected
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        return @($Value | ForEach-Object { Protect-PcSetupLogData -Value $_ })
    }
    return Protect-PcSetupLogText -Value $Value
}

function Protect-PcSetupCommandArguments {
    param([object[]]$Arguments = @())

    $protected = @()
    $redactNext = $false
    foreach ($argument in @($Arguments)) {
        $text = [string]$argument
        if ($redactNext) {
            $protected += '[REDACTED]'
            $redactNext = $false
            continue
        }
        if ($text -match '^(?<name>--?[^=]+)=(?<value>.*)$') {
            $argumentName = [string]$Matches['name']
            if ($argumentName -match $script:SensitiveNamePattern) {
                $protected += ($argumentName + '=[REDACTED]')
                continue
            }
        }
        if ($text -match '^--?' -and $text -match $script:SensitiveNamePattern) {
            $protected += $text
            $redactNext = $true
            continue
        }
        if ($text -match '^(?<name>[A-Za-z_][A-Za-z0-9_]*)=(?<value>.*)$') {
            $environmentName = [string]$Matches['name']
            if ($environmentName -match $script:SensitiveNamePattern) {
                $protected += ($environmentName + '=[REDACTED]')
                continue
            }
        }
        $protected += Protect-PcSetupLogText -Value $text
    }
    return $protected
}

function New-PcSetupExecutionLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$Operation,
        [string]$SessionId = ([guid]::NewGuid().ToString('N'))
    )

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }
    $safeOperation = [regex]::Replace($Operation.ToLowerInvariant(), '[^a-z0-9_-]+', '-')
    $path = Join-Path $Directory ('execution-' + $safeOperation.Trim('-') + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $SessionId.Substring(0, 8) + '.jsonl')
    return [pscustomobject]@{ SchemaVersion = 1; SessionId = $SessionId; Operation = $Operation; Path = $path }
}

function Write-PcSetupExecutionEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Log,
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory)][ValidateSet('Started','Info','Pending','Succeeded','Failed')][string]$Status,
        [Parameter(Mandatory)][string]$Message,
        [string]$Command = '',
        [object[]]$Arguments = @(),
        [System.Collections.IDictionary]$Data
    )

    $record = [ordered]@{
        SchemaVersion = 1
        OccurredAt    = (Get-Date).ToString('o')
        SessionId     = [string]$Log.SessionId
        Operation     = [string]$Log.Operation
        Stage         = $Stage
        Status        = $Status
        Message       = Protect-PcSetupLogText -Value $Message
    }
    if (-not [string]::IsNullOrWhiteSpace($Command)) {
        $record.Command = Protect-PcSetupLogText -Value $Command
        $record.Arguments = @(Protect-PcSetupCommandArguments -Arguments $Arguments)
    }
    if ($null -ne $Data -and $Data.Count -gt 0) {
        $record.Data = Protect-PcSetupLogData -Value $Data
    }
    $line = $record | ConvertTo-Json -Depth 10 -Compress
    $encoding = New-Object Text.UTF8Encoding($false)
    [IO.File]::AppendAllText([string]$Log.Path, $line + [Environment]::NewLine, $encoding)
    return [pscustomobject]$record
}

Export-ModuleMember -Function New-PcSetupExecutionLog, Write-PcSetupExecutionEvent, Protect-PcSetupCommandArguments, Protect-PcSetupLogData
