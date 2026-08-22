@{
    SchemaVersion = '1.0'
    LinuxUser     = 'codex'
    ProjectRoot   = '/home/{LinuxUser}/Dev'
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
