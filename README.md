# pc-setup

Automação configurável para transformar uma instalação nova ou uma máquina usada com Windows 11 Pro em um computador pessoal pronto para uso.

O objetivo é partir de qualquer Windows 11 Pro compatível, revisar um único perfil versionado e executar `INSTALAR.cmd`. O projeto planeja, aplica e valida o estado solicitado sem guardar senhas, tokens ou chaves no repositório. Reaplicações usam `ATUALIZAR.cmd`.

Para uma instalação começando pelo pendrive, use o guia completo em [`imagem-windows/README.md`](imagem-windows/README.md). A mídia fica responsável apenas por instalar o Windows; aplicativos, recursos opcionais, usuários e personalização são tratados depois pelo `pc-setup`.

> [!IMPORTANT]
> `config/machine.psd1` é um perfil versionado de referência, não uma configuração universal. Revise usuários, armazenamento, recursos e pacotes antes de executar `INSTALAR.cmd`.

## Comportamento do perfil versionado

- valida exatamente o `EditionID` Professional do Windows 11, a partir da build 22000;
- usa o volume do Windows detectado em tempo de execução;
- pergunta se deve usar um único segundo disco fixo com volume NTFS saudável, quando houver;
- sem segundo disco, cria `Dados` no volume do Windows;
- cria a estrutura de dados configurada;
- cria ou habilita as contas configuradas e garante sua associação ao grupo local `Usuários`, permitindo o primeiro logon;
- preserva o usuário diário como administrador até a conta de recuperação ser testada;
- aplica ACLs isolando dados pessoais e projetos, com backup e rollback;
- valida a virtualização antes de habilitar Hyper-V, Windows Sandbox, Virtual Machine Platform e WSL;
- instala ou atualiza Chrome, Bitwarden, WinRAR, Google Drive, ferramentas de desenvolvimento e launchers de jogos pelo Winget, com escopo explícito por pacote;
- atualiza o WSL 2 e prepara, na mesma distribuição Ubuntu, os usuários Linux diário e `agent`;
- resolve a release estável atual do `ai-jail`, exige o digest SHA-256 publicado pelo GitHub, instala/atualiza o Codex e fornece um launcher isolado;
- permite que o usuário diário administre o Hyper-V sem torná-lo administrador geral do Windows;
- gera relatórios JSON de plano, aplicação, versões instaladas pelo Winget e validação;
- apenas informa o estado do BitLocker, sem configurá-lo.

A conta pública fica habilitada como usuário padrão. A VM opcional e o plano de fundo ficam desabilitados. O debloat é configurado, mas continua sendo uma etapa separada com confirmação própria.

## Pré-requisitos

1. Termine o Windows Update e instale os drivers.
2. Habilite manualmente a Proteção do Sistema no volume do Windows.
3. Confirme que o Windows está ativado.
4. Revise [`config/machine.psd1`](config/machine.psd1).
5. Confirme no arquivo os nomes das contas, a política de armazenamento, os recursos opcionais e os pacotes.

O setup não habilita a Proteção do Sistema sozinho. Se não conseguir criar e consultar o ponto de restauração obrigatório, nenhuma etapa de aplicação começa.

## Executar

A forma mais simples é dar duplo clique em `INSTALAR.cmd`. A primeira execução pode começar em qualquer conta Windows capaz de fornecer credenciais administrativas no UAC.

O arquivo:

1. carrega `config\machine.psd1` e planeja Windows e WSL;
2. solicita permissão de Administrador;
3. mostra o plano e o disco escolhido;
4. pede `S` uma única vez;
5. aplica e valida as configurações de máquina em processo elevado;
6. se a conta atual não for a conta diária configurada, pede para entrar nela e executar o mesmo arquivo novamente;
7. na conta diária, aplica pacotes e personalização no perfil correto, elevando somente instaladores de máquina que precisarem;
8. aplica e valida os ambientes WSL da conta diária, primeiro o usuário padrão e depois o `agent`.

Pacotes com escopo `machine` podem abrir um pedido de UAC durante a fase da conta diária. Isso é esperado: o Winget continua disponível no perfil correto, enquanto somente o instalador que precisa alterar a máquina recebe elevação.

Se for necessário reiniciar, reinicie o Windows e clique no mesmo arquivo novamente. A aplicação será retomada do ponto salvo. Em uma máquina usada, a fase administrativa pode criar a conta diária configurada; depois, entre nessa conta e clique novamente em `INSTALAR.cmd`. Se pacotes, personalização ou WSL falharem depois da conclusão do Windows, uma nova execução retoma somente as fases da conta diária, desde que configuração e projeto não tenham mudado. Senhas de contas novas ainda são solicitadas em prompt seguro.

### Atualizar ou reaplicar depois

Depois de alterar `config/machine.psd1`, os perfis ou os scripts, dê duplo clique em `ATUALIZAR.cmd`. Ele funciona como uma reconciliação idempotente:

1. planeja o Windows e os ambientes WSL habilitados para a conta diária;
2. mostra, aplica e valida o estado do Windows pelo mesmo fluxo protegido do instalador;
3. interrompe e pede reinício quando um recurso do Windows exigir;
4. reaplica e valida primeiro o usuário Linux padrão e depois o `agent`.

Esse fluxo atualiza pacotes com política de versão atual, incluindo Winget, APT, `Agent.Harness.Version = 'latest'` e `AiJail.Version = 'latest'`. Ele não atualiza o próprio repositório por Git e não cria, lê nem copia credenciais.

`INSTALAR.cmd` e `ATUALIZAR.cmd` usam o mesmo orquestrador. O primeiro comunica a instalação inicial; o segundo comunica a reconciliação de uma máquina já configurada. Depois que uma execução termina por completo, `ATUALIZAR.cmd` volta a conferir e reaplicar normalmente o estado desejado.

### Limites da reconciliação

O modo suportado é aditivo e não destrutivo. O projeto cria, habilita, instala e atualiza o que está configurado, mas não desinstala automaticamente pacotes que saíram da lista, não apaga contas ou diretórios e não desabilita recursos que passaram para `false`. Mudanças de remoção devem ser executadas e revisadas separadamente.

Isso permite usar o mesmo fluxo em máquinas novas ou usadas sem transformar uma alteração de configuração em exclusão silenciosa. O `verify.ps1` valida o estado prometido pelo perfil, não exige que a máquina contenha somente os itens declarados.

### Execução manual

Abra o **Windows PowerShell 5.1 como Administrador** na pasta do projeto:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\bootstrap.ps1 -Config .\config\machine.psd1 -Plan
```

Leia o plano mostrado e o caminho do relatório. Se a escolha do disco, usuários, recursos e programas estiver correta:

```powershell
.\bootstrap.ps1 -Config .\config\machine.psd1 -Apply
```

O recibo inclui a impressão SHA-256 dos scripts, da configuração e dos perfis de pacotes. Qualquer mudança relevante exige gerar o plano novamente.

As senhas são solicitadas somente para contas habilitadas que ainda não existam. Elas permanecem apenas na memória do processo.

Se recursos do Windows exigirem reinício, o script para e mostra a instrução. Reinicie e execute o mesmo comando `-Apply`. A retomada valida e reutiliza o ponto pertencente àquela aplicação; um ponto antigo de outra execução nunca é aceito.

Ao terminar:

```powershell
.\verify.ps1 -Config .\config\machine.psd1
```

O verificador classifica cada item como `PASS`, `WARN`, `FAIL` ou `INFO`. Avisos exigem revisão; falhas fazem o comando retornar código 1.

## Saída da execução

O plano apresenta:

- perfil e arquivo de configuração usados;
- volume atual do Windows e raiz escolhida para dados;
- recursos que serão habilitados;
- diretórios e contas que serão criados;
- permissões que serão aplicadas;
- IDs dos programas e disponibilidade de fallback offline;
- configuração prevista para WSL e personalização;
- estado do debloat separado.

Na aplicação, cada etapa mostra `OK`, `CRIADO`, `APLICAR`, `WINGET`, `OFFLINE`, `RECOVERY` ou uma mensagem de erro. Códigos de erro de ferramentas externas são tratados como falha.

## Armazenamento

O perfil padrão usa:

```powershell
SecondaryDiskPolicy    = 'Ask'
OnMultipleCandidates  = 'Stop'
SingleDiskFallbackRoot = '{SystemRoot}\Dados'
AllowRemovableVolumes  = $false
```

Isso significa:

- um único volume NTFS saudável em um segundo disco fixo: pergunta se deve usá-lo;
- nenhum segundo disco: usa `Dados` no volume do Windows;
- segundo disco sem volume NTFS utilizável: interrompe e pede preparação no Gerenciamento de Disco;
- vários volumes candidatos: interrompe para não escolher por adivinhação;
- unidade removível: não é escolhida automaticamente.

Modelo, tamanho, rótulo, barramento e letra não são fixados. A raiz escolhida no plano precisa ser a mesma na aplicação.

Para forçar uma máquina com somente um disco, use como base [`config/examples/machine-one-disk.psd1`](config/examples/machine-one-disk.psd1).

## Diretórios e permissões

Os nomes abaixo são relativos à raiz de dados escolhida:

```text
Apps
Games
Dev
Data\<usuario principal>
Shared
Downloads
VMs
Containers
```

As ACLs protegidas são:

- `Dev`: usuário principal com modificação;
- dados pessoais: somente usuário principal, SYSTEM e Administradores.

O agente não usa uma pasta Windows dedicada. Ele roda como o usuário Linux `agent`, sem `sudo`, dentro do WSL e do `ai-jail`. O workspace Linux compartilhado fica em `/home/agent/Dev`; `felipe` e `agent` pertencem ao grupo `pcsetup-agent`.

Os nomes das contas são configuráveis. Consulte os papéis e limites de cada conta em [`usuarios/README.md`](usuarios/README.md).

Antes da alteração, o script exporta as ACLs para `%ProgramData%\pc-setup\acl-backups`. Se a própria etapa de ACL falhar, ela tenta restaurar os backups daquela etapa. Falhas posteriores não provocam rollback automático das ACLs.

Perfis do Windows, `AppData`, `ProgramData` e componentes do sistema não são movidos.

A criação dessas pastas não redireciona automaticamente bibliotecas da Steam, dados do Docker ou o destino escolhido pelos instaladores. Esses ajustes continuam específicos de cada programa.

## Programas

Os perfis ficam em [`config/packages`](config/packages):

- `base`: Chrome, Bitwarden, WinRAR e Google Drive;
- `development`: Git, PowerShell, Windows Terminal, VS Code e Docker Desktop;
- `gaming`: Steam e Epic Games Launcher.

O Winget consulta a fonte oficial configurada no Windows e tenta instalar a versão atual. Cada linha do perfil declara `ID|escopo`; `Packages.InstallScope` é apenas o padrão para linhas sem escopo. Chrome e os aplicativos tradicionais usam `machine`; Bitwarden e Windows Terminal usam `user`, pois seus instaladores atuais são próprios da conta. Em caso de falha, um instalador offline só é aceito quando consta em [`config/offline-installers.psd1`](config/offline-installers.psd1), declara o mesmo escopo, existe dentro da pasta permitida e tem SHA-256 idêntico ao manifesto.

O fallback offline pode estar atrás da versão publicada. O inventário registra o que foi realmente instalado e a próxima execução com acesso à internet tenta atualizar novamente.

Ao final da etapa, as versões realmente encontradas pelo `winget export --include-versions` são registradas em `%LOCALAPPDATA%\pc-setup\winget-installed.json` da conta diária e arquivadas junto aos relatórios da fase do usuário.

## WSL e agente de IA

O bootstrap principal configura os recursos globais do WSL. Na instalação inicial, `INSTALAR.cmd` aplica dois perfis na mesma distribuição: primeiro `DailyUser`, depois `Agent`. Em manutenções posteriores, `ATUALIZAR.cmd` reconcilia os mesmos perfis. Ambos devem ser executados na conta Windows diária, e o perfil do agente não troca o usuário padrão da distribuição.

Os comandos, perfis convergentes e a decisão entre `/mnt/d/Dev` e o filesystem Linux estão em [`wsl/README.md`](wsl/README.md). Os relatórios WSL incluem as versões APT, do harness e do `ai-jail` realmente encontradas no manifesto instalado.

O perfil padrão instala a versão atual do pacote NPM `@openai/codex` para o usuário Linux `agent`. A autenticação é feita manualmente uma vez e permanece no estado explicitamente liberado do agente. `AGENTE.cmd` solicita e canonicaliza um diretório, recusa raízes amplas e o usa como fronteira de acesso do `ai-jail`. Consulte o modelo de segurança e as limitações em [`docs/AGENTE-IA.md`](docs/AGENTE-IA.md).

## Criar um perfil de máquina

Use `config/machine.psd1` como referência e altere, principalmente:

- `Machine.PrimaryUser`;
- nomes, funções e `Enabled` das contas Windows;
- harness, workspace, capacidades e ambiente WSL do agente;
- política do segundo disco;
- recursos opcionais;
- perfis de programas;
- ambientes WSL por conta e os respectivos perfis Linux.

Exemplo:

```powershell
.\bootstrap.ps1 -Config .\config\exemplo-maquina.psd1 -Plan
.\bootstrap.ps1 -Config .\config\exemplo-maquina.psd1 -Apply
```

Veja todas as decisões em [`config/README.md`](config/README.md).

## Recuperação e relatórios

O Windows limita `Checkpoint-Computer` a um ponto por período de 24 horas. Por isso, uma aplicação cria um ponto único. Scripts internos o validam e reutilizam; a continuação depois do reinício usa o mesmo identificador salvo em `%ProgramData%\pc-setup\apply-state.json`.

Executar um script de alteração diretamente com `-Apply` exige um novo ponto. `-Plan`, `verify.ps1`, testes e o lançador da VM não alteram a configuração do Windows e não criam ponto.

Relatórios e estado das operações de máquina ficam em `%ProgramData%\pc-setup`. Inventário Winget, personalização e ambientes WSL ficam em `%LOCALAPPDATA%\pc-setup` da conta diária. Um ponto de restauração protege configurações e arquivos de sistema, mas não substitui backup dos arquivos pessoais.

Procedimentos para aplicação incompleta, ACLs, WSL, checkpoints e restauração estão em [`docs/RECUPERACAO.md`](docs/RECUPERACAO.md).

## Etapas opcionais

### Plano de fundo

Uma imagem local pode ser adicionada ao projeto e indicada em `Personalization.WallpaperPath`. A alteração é aplicada ao usuário que executa o bootstrap quando `Enabled = $true`.

### Debloat

O debloat não faz parte do bootstrap de aplicação. O perfil Felipe fixa Win11Debloat `2026.07.11`, valida o SHA-256 e aplica `RunDefaults` silenciosamente para todos os usuários, sem `RemoveGamingApps`. A execução exige leitura da documentação e confirmação explícita. Veja [`docs/DEBLOAT.md`](docs/DEBLOAT.md).

### Contas e VMs opcionais

A conta pública fica habilitada como usuário padrão, com Edge e Chrome destinados à navegação e sessão persistente. O agente usa `ai-jail` por padrão; sua configuração reserva uma VM opcional, mas o projeto não cria nenhuma VM automaticamente.

## Testes do projeto

Os testes não alteram o Windows nem criam ponto real:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run-all.ps1
```

A CI executa a mesma suíte em Windows PowerShell 5.1, valida PowerShell e PSD1, roda o PSScriptAnalyzer e verifica os scripts WSL com `bash -n` e ShellCheck.

Consulte também [`SECURITY.md`](SECURITY.md) para o modelo de suporte e reporte de vulnerabilidades. O mantenedor ainda precisa escolher e publicar uma licença antes de declarar permissões de reutilização.

## Referências

- [Akitando #114](https://akitaonrails.com/2022/02/15/akitando-114-o-melhor-setup-dev-com-arch-e-wsl2/)
- [System Protection](https://support.microsoft.com/en-us/windows/experience/backup-recovery/system-protection)
- [Checkpoint-Computer](https://learn.microsoft.com/pt-br/powershell/module/microsoft.powershell.management/checkpoint-computer?view=powershell-5.1)
- [Windows 11 release information](https://learn.microsoft.com/windows/release-health/windows11-release-information)
- [Arquivos entre Windows e WSL](https://learn.microsoft.com/windows/wsl/filesystems)
- [Winget export](https://learn.microsoft.com/windows/package-manager/winget/export)
- [Win11Debloat](https://github.com/Raphire/Win11Debloat)
