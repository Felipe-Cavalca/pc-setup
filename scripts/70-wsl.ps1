#requires -RunAsAdministrator
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw 'wsl.exe nao encontrado. Reinicie apos habilitar os recursos do Windows.'
}

wsl --update
Write-Host 'WSL atualizado.'
Write-Host 'Distribuicoes sao configuradas por usuario. Instale a distro pessoal em Felipe e a distro CodexDev no contexto do usuario Codex.'
Write-Host 'Para projetos com muitos arquivos pequenos, considere manter o checkout dentro do filesystem Linux/VHDX em vez de /mnt/d se a performance virar problema.'
