@{
    SchemaVersion = '1.0'

    # Fallback opcional. Caminhos sao relativos a Packages.OfflineInstallerDirectory.
    # O SHA-256 e obrigatorio para impedir a execucao de um arquivo diferente do revisado.
    Installers = @(
        # @{
        #     PackageId = 'Google.Chrome'
        #     File      = 'ChromeStandaloneSetup64.exe'
        #     Sha256    = 'COLOQUE_AQUI_O_SHA256_DO_ARQUIVO'
        #     Arguments = @('/silent', '/install')
        # }
    )
}
