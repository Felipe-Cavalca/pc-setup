# Debloat configurado

O perfil Felipe usa `Raphire/Win11Debloat` na release fixa `2026.07.11`. O wrapper baixa somente o ZIP dessa tag, compara o SHA-256 versionado e interrompe antes da extração se o conteúdo divergir.

## Comportamento definido

A execução chama:

```powershell
Win11Debloat.ps1 -RunDefaults -Silent -AppRemovalTarget AllUsers
```

Isso aplica os ajustes e a seleção padrão de aplicativos da release para todos os usuários. O wrapper não envia `-RemoveGamingApps` nem `-ForceRemoveEdge`; Xbox/Game Bar e Edge não são removidos por esses parâmetros.

O preset padrão inclui mudanças de privacidade, sugestões, pesquisa e recursos de IA, além da lista padrão de aplicativos da ferramenta. A lista exata fica em `Config/Apps.json` e `Config/DefaultSettings.json` da tag fixada.

## Executar

O debloat permanece separado do bootstrap principal porque remove aplicativos e muda diversas preferências. Depois de concluir o setup base, leia esta página e execute em Windows PowerShell 5.1 como Administrador:

```powershell
.\scripts\50-debloat-akita.ps1 -Config .\config\machine.psd1 -Plan
.\scripts\50-debloat-akita.ps1 -Config .\config\machine.psd1 -Apply -ConfirmReviewed
```

A aplicação cria e valida um ponto de restauração antes do download. Por causa do limite do Windows para `Checkpoint-Computer`, pode ser necessário aguardar o intervalo de 24 horas depois do ponto criado pelo setup base.

## Depois

Reinicie e teste Windows Update, Microsoft Store, Defender, pesquisa, menu Iniciar, Edge e jogos. Execute `verify.ps1` novamente.

Referências oficiais:

- [release 2026.07.11](https://github.com/Raphire/Win11Debloat/releases/tag/2026.07.11)
- [configurações padrão](https://github.com/Raphire/Win11Debloat/wiki/Default-Settings)
- [remoção de aplicativos](https://github.com/Raphire/Win11Debloat/wiki/App-Removal)
