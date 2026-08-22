# Debloat opcional

O perfil padrão não executa debloat. Esta etapa é isolada porque remove aplicativos e muda várias preferências do Windows; o ganho é subjetivo e o risco é maior que nas demais etapas.

O wrapper usa `Raphire/Win11Debloat` na release `2026.07.11`, mas não executa uma URL flutuante nem escolhe um preset silencioso. Ele baixa o arquivo da tag, compara o SHA-256 configurado e abre a interface oficial para revisão.

## Habilitar conscientemente

1. Leia as mudanças da release e os arquivos `Config/Apps.json` e `Config/DefaultSettings.json` do projeto externo.
2. Baixe a mesma tag por um caminho confiável e calcule o SHA-256 do ZIP.
3. Em `config/machine.psd1`, defina `Debloat.ArchiveSha256` e mude `Debloat.Enabled` para `$true`.
4. Gere novamente o plano do setup.
5. Execute em Windows PowerShell 5.1 como Administrador:

```powershell
.\scripts\50-debloat-akita.ps1 -Config .\config\machine.psd1 -Plan
.\scripts\50-debloat-akita.ps1 -Config .\config\machine.psd1 -Apply -ConfirmReviewed
```

O segundo comando cria e valida um ponto de restauração antes do download. Hash ausente ou divergente interrompe a execução.

## Depois

Reinicie e teste Windows Update, Microsoft Store, Defender, dispositivos, pesquisa, menu Iniciar, Xbox e jogos utilizados. Execute `verify.ps1` novamente.

O objetivo é remover apenas o que foi compreendido e revisado, mantendo o Windows recuperável.
