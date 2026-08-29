# Personalização do Windows

O personalizador converge a aparência e as pastas da conta diária sem misturar essas decisões com o debloat geral.

## Como executar

- `INSTALAR.cmd`: aplica automaticamente quando `ApplyOnInstall = $true`;
- `ATUALIZAR.cmd`: pergunta antes de reaplicar quando `PromptOnUpdate = $true`;
- `PERSONALIZAR.cmd`: mostra somente o plano de personalização, pede `S`, solicita a credencial administrativa para o ponto de restauração e aplica a etapa.

Execute o launcher manual na conta configurada em `Accounts.DailyUser.Name`. O Explorador do Windows é reiniciado no final; a barra de tarefas pode desaparecer por alguns segundos.

## Perfil padrão

O perfil versionado:

- usa o tema escuro;
- oculta a caixa de pesquisa e o botão Visão de Tarefas;
- tenta desabilitar consultas, resultados e destaques da web na pesquisa do Windows;
- limpa os aplicativos fixados no menu Iniciar e mantém a possibilidade de fixar itens depois;
- seleciona a visualização “Todos” em categorias;
- deixa somente Configurações junto ao botão de energia;
- desabilita o início rápido e o modo em segundo plano do Edge e remove entradas de inicialização do perfil;
- desinstala o OneDrive sem apagar a pasta de dados que já existia e oculta o atalho residual do Explorador;
- remove Outlook e LinkedIn dos perfis existentes e do provisionamento de novos usuários;
- não remove Vincular ao Celular nem o componente Cross Device.

As políticas `StartupBoostEnabled` e `BackgroundModeEnabled` do Edge são aplicadas na fase administrativa em `HKLM`. A pesquisa web usa `DisableWebSearch`, `ConnectedSearchUseWeb` e `EnableDynamicContentInWSB`, também em `HKLM`. No perfil pessoal, `WebSearchMode = 'Aggressive'` acrescenta `DisableSearchBoxSuggestions` no hive protegido da conta diária e desabilita Bing/Cortana na pesquisa do perfil. Esse complemento é necessário porque a política documentada `DoNotUseWebResults` não é suportada no Windows 11 Pro; por isso, o resultado continua sendo de melhor esforço e pode mudar em uma atualização do Windows.

A verificação da fase Windows não exige antecipadamente as políticas de personalização. Depois dessa verificação, `82-personalization-machine.ps1` cria e confirma em `HKLM` as políticas do Edge e da pesquisa web. Uma tarefa temporária executada como `LocalSystem` usa o provedor oficial WMI Bridge para os atalhos do Iniciar e o layout da barra, sendo removida ao terminar. Em seguida, a fase da conta diária aplica e valida as configurações de `HKCU`.

A limpeza dos fixados usa o `start2.bin` vazio da versão do Win11Debloat já fixada e validada por SHA-256 no projeto. O estado anterior recebe uma cópia em `%LOCALAPPDATA%\pc-setup\backups\start-menu`.

A visualização por categoria depende da implementação presente nas builds recentes do Windows 11. Em versões que ainda não oferecem esse modo, o Registro pode aceitar a configuração sem alterar a interface até a atualização do Windows.

## Barra de tarefas

A ordem desejada para a conta diária é:

1. Explorador de Arquivos;
2. Brave;
3. Visual Studio Code;
4. Terminal;
5. Proton Mail;
6. Windows Sandbox.

O projeto não grava o valor binário e não documentado `Taskband`. Ele gera XML no formato oficial e tenta aplicá-lo à conta diária pelo CSP `StartLayout`. `ReplaceDefaultPins = $true` remove os fixados padrão. Cada item recebe `PinGeneration`, permitindo desafixar, fixar novos programas e reorganizar a barra depois da aplicação.

Algumas builds recusam a instância por usuário do WMI Bridge mesmo quando a política existe na edição Pro. Nesse caso, o relatório registra `TaskbarStatus = ManualRequired`, a instalação continua com as demais personalizações e a barra fica livre para ajuste manual. O projeto não usa alterações binárias não documentadas como fallback.

Para alterar o padrão, edite `Personalization.Taskbar.Pins`. Incremente `PinGeneration` quando quiser que itens removidos anteriormente sejam fixados outra vez e execute `PERSONALIZAR.cmd` ou aceite a personalização no `ATUALIZAR.cmd`. O layout normalmente aparece após sair e entrar na conta; builds recentes podem aplicá-lo imediatamente. Consulte a [documentação oficial de personalização da barra de tarefas](https://learn.microsoft.com/windows/configuration/taskbar/pinned-apps).

Brave, Visual Studio Code, Terminal e Proton Mail precisam estar instalados, e Windows Sandbox precisa estar habilitado, antes de aparecerem para fixação.

## Tela de bloqueio

`Personalization.LockScreen` registra a imagem desejada e desabilita o Spotlight do perfil. No Windows 11 Pro comum, o CSP oficial que força uma imagem só é suportado em cenários educacionais ou de computador compartilhado e também impediria a troca manual. Por isso, o padrão usa `Mode = 'Manual'`: a imagem é copiada para `%LOCALAPPDATA%\pc-setup\assets`, e `PERSONALIZAR.cmd` abre a página correta para selecioná-la.

O bloco também documenta `ShowOnSignIn` e `Status`. O padrão usa a mesma imagem na entrada e nenhum aplicativo de status. Essas duas escolhas são confirmadas manualmente na página de bloqueio para manter o Windows Pro editável.

## Pastas pessoais

As pastas declaradas em `KnownFolders` permanecem nos caminhos padrão do perfil Windows:

```text
C:\Users\Felipe\Desktop
C:\Users\Felipe\Documents
C:\Users\Felipe\Downloads
C:\Users\Felipe\Music
C:\Users\Felipe\Pictures
C:\Users\Felipe\Videos
```

O padrão `RestoreKnownFoldersToProfile = $true` corrige instalações feitas com a configuração anterior. O script usa a API de pastas conhecidas do Windows, copia o conteúdo de volta com `robocopy`, sem seguir junções, atualiza o caminho reconhecido pelo sistema e não exclui a origem antiga. Depois de conferir os arquivos, a árvore legada pode ser removida manualmente.

Na raiz de dados, a estrutura do usuário contém `Apps`, `Containers`, `Dev`, `Drive`, `Games` e `VMs`. A entrada `Data` é uma junção para `C:\Users\Felipe`; ela oferece navegação conveniente, mas não move nem duplica o perfil. Um caminho real já existente no lugar da junção interrompe a etapa sem apagar nada.

`GoogleDrive.Enabled = $true` registra `Storage.Paths.Drive` como ponto de montagem do Google Drive em modo streaming, usando a [configuração avançada documentada pelo Google](https://knowledge.workspace.google.com/admin/drive/advanced-drive-for-desktop-configuration?hl=pt). A pasta precisa estar vazia na primeira configuração. O script não faz login, não guarda credenciais e não move o cache local do cliente. Se o Google Drive já estiver aberto, a nova localização pode aparecer somente depois de reiniciar o aplicativo.

Esse mecanismo não muda automaticamente os diretórios internos de Docker, Steam ou Epic. Eles continuam documentados como integrações próprias porque cada aplicativo possui seu formato e seu ciclo de vida.

## Plano de fundo

Coloque a imagem em `config\wallpapers` e informe o caminho relativo:

```powershell
WallpaperPath = 'config\wallpapers\minha-imagem.jpg'
```

Com `WallpaperPath = ''`, todo o restante é aplicado e o plano de fundo atual é preservado.

## Aplicativos Proton

`Proton.ProtonMail` e `Proton.ProtonVPN` estão no perfil `base` como pacotes opcionais do Winget. O instalador tenta obter a versão atual; uma falha nesses itens fica como pendência e não interrompe sozinha o setup.
