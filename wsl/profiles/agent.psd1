@{
    SchemaVersion    = '1.0'
    LinuxUser        = 'agent'
    ProjectRoot      = '/home/{LinuxUser}/Dev'
    SetAsDefaultUser = $false
    RequireNoSudo    = $true
    SharedGroup      = 'pcsetup-agent'
    # O usuario Linux diario e resolvido pelo ambiente Default da mesma distribuicao.
    SharedWith       = @()
    ProjectRootMode  = '2770'
    Packages         = @(
        'bubblewrap'
        'ca-certificates'
        'curl'
        'git'
        'jq'
        'nodejs'
        'npm'
        'unzip'
        'zip'
    )
    AiJail = @{
        Enabled      = $true
        Repository   = 'akitaonrails/ai-jail'
        # latest consulta a release estavel atual e exige o digest SHA-256 publicado pelo GitHub.
        Version      = 'latest'
        Architecture = 'x86_64'
        Sha256       = ''
        RequireAssetDigest = $true
    }
}
