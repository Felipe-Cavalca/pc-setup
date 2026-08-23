@{
    SchemaVersion = '1.0'
    LinuxUser     = 'usuario'
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
