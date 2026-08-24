#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot

function Assert-True($Value, [string]$Message) {
    if (-not $Value) { throw $Message }
}

$markdownFiles = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.md' | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
Assert-True ($markdownFiles.Count -ge 12) 'A validacao deve alcançar todos os documentos Markdown do projeto.'

$brokenLinks = @()
foreach ($file in $markdownFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    Assert-True (-not [string]::IsNullOrWhiteSpace($content)) "Documento vazio: $($file.FullName)"
    Assert-True ($content -match '^#\s+\S') "Documento sem titulo H1 inicial: $($file.FullName)"
    Assert-True (-not $content.Contains([char]0xFFFD)) "Documento contem caractere de substituicao de encoding: $($file.FullName)"
    $fenceCount = [regex]::Matches($content, '(?m)^```').Count
    Assert-True (($fenceCount % 2) -eq 0) "Bloco de codigo Markdown sem fechamento: $($file.FullName)"

    foreach ($match in [regex]::Matches($content, '(?<!!)\[[^\]]+\]\((?<target>[^)]+)\)')) {
        $target = $match.Groups['target'].Value.Trim().Trim('<','>')
        if ($target -match '^(?i:https?://|mailto:|#)') { continue }
        $relativePath = ($target -split '[?#]', 2)[0]
        if ([string]::IsNullOrWhiteSpace($relativePath)) { continue }
        $decodedPath = [Uri]::UnescapeDataString($relativePath).Replace('/', [IO.Path]::DirectorySeparatorChar)
        $resolvedPath = [IO.Path]::GetFullPath((Join-Path $file.DirectoryName $decodedPath))
        if (-not (Test-Path -LiteralPath $resolvedPath)) {
            $brokenLinks += "$($file.FullName): $target"
        }
    }
}
Assert-True ($brokenLinks.Count -eq 0) "Links relativos quebrados: $($brokenLinks -join '; ')"

$requiredDocumentation = @{
    'README.md'                           = @('ai-memory', '/mnt/d/Dev', '0x80072ee7')
    'config\README.md'                    = @('Agent.Memory', 'ProjectStrategy', 'AI_MEMORY_AUTH_TOKEN')
    'docs\AGENTE-IA.md'                   = @('finalize-session', 'bootstrap --dry-run', '127.0.0.1')
    'docs\RECUPERACAO.md'                 = @('0x80072ee7', 'InternetOpenUrl() failed')
    'SECURITY.md'                         = @('Memória e dados sensíveis', 'ai-memory')
    'wsl\README.md'                       = @('ai-memory', '/mnt/d/Dev', 'filesystem Linux')
    'imagem-windows\docs\TESTE-EM-VM.md' = @('ai-memory', 'MCP')
}
foreach ($relativePath in $requiredDocumentation.Keys) {
    $content = Get-Content -LiteralPath (Join-Path $root $relativePath) -Raw
    foreach ($expectedText in $requiredDocumentation[$relativePath]) {
        Assert-True ($content.Contains($expectedText)) "Documentacao ausente em ${relativePath}: $expectedText"
    }
}

$mainReadme = Get-Content -LiteralPath (Join-Path $root 'README.md') -Raw
Assert-True ($mainReadme -notmatch '(?m)^Downloads\s*$') 'A pasta Downloads removida nao deve voltar à estrutura documentada.'

Write-Host "PASS: $($markdownFiles.Count) documentos Markdown e links relativos validados." -ForegroundColor Green
