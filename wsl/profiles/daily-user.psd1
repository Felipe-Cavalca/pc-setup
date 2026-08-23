@{
    SchemaVersion = '1.0'
    LinuxUser     = 'felipe'
    ProjectRoot   = '/home/{LinuxUser}/Dev'
    SetAsDefaultUser = $true
    Packages      = @(
        'build-essential'
        'ca-certificates'
        'curl'
        'git'
        'jq'
        'unzip'
        'zip'
    )
}
