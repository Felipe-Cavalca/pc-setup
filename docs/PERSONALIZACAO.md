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
- desabilita consultas, resultados e sugestões da web na pesquisa do Windows;
- limpa os aplicativos fixados no menu Iniciar e mantém a possibilidade de fixar itens depois;
- seleciona a visualização “Todos” em categorias;
- deixa somente Configurações junto ao botão de energia;
- desabilita o início rápido e o modo em segundo plano do Edge e remove entradas de inicialização do perfil;
- desinstala o OneDrive sem apagar a pasta de dados que já existia e oculta o atalho residual do Explorador;
- remove o aplicativo LinkedIn do perfil diário;
- não remove Vincular ao Celular nem o componente Cross Device.

As políticas `StartupBoostEnabled` e `BackgroundModeEnabled` do Edge são aplicadas na fase administrativa em `HKLM`. A fase da conta diária apenas remove entradas de inicialização do próprio perfil; ela não tenta gravar na área protegida `HKCU\Software\Policies`.

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

O projeto não grava diretamente o valor binário e não documentado `Taskband` do perfil. No Windows 11, a automação suportada pela Microsoft usa XML por política, pacote de provisionamento ou CSP e pode reaplicar o layout, impedir remoções ou substituir escolhas do usuário. Para manter a configuração pessoal e editável, fixe esses seis itens manualmente na ordem acima e desafixe Edge, Microsoft Store e Outlook. Consulte a [documentação oficial de personalização da barra de tarefas](https://learn.microsoft.com/windows/configuration/taskbar/pinned-apps).

Brave, Visual Studio Code, Terminal e Proton Mail precisam estar instalados, e Windows Sandbox precisa estar habilitado, antes de aparecerem para fixação.

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
