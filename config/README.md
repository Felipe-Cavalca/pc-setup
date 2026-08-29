# Configuração

`machine.psd1` guarda decisões não secretas e funciona como perfil versionado de referência. Ele não deve ser executado sem revisão. Os scripts não dependem de letra, modelo ou tamanho fixo de disco.

Nunca coloque no arquivo senhas, tokens, chaves de produto, certificados ou chaves de recuperação.

`INSTALAR.cmd`, `ATUALIZAR.cmd` e `PERSONALIZAR.cmd` carregam `config\machine.psd1`. Para outro perfil, preserve uma cópia do arquivo atual, substitua o conteúdo de `machine.psd1` pelo perfil revisado e use um dos launchers da raiz. Os arquivos `.ps1` são complementos internos e não são entradas de uso normal.

## Execução

O perfil Felipe usa `Execution.Mode = 'Interactive'` para perguntar pelo disco de dados durante o plano. A aplicação reutiliza a escolha registrada, sem perguntar novamente. Senhas de contas novas continuam sendo coletadas em prompt seguro e ficam apenas na memória.

Use `Unattended` somente em perfis cuja política de disco seja `UseIfAvailable` ou `Ignore`.

`Runtime.RequirePlanBeforeApply = $true` exige que a configuração e a raiz de dados coincidam com o último plano salvo.

## Reconciliação

`Reconciliation.Mode = 'Additive'` é o único modo suportado. As quatro opções de remoção permanecem `false`: desabilitar recursos, remover contas, desinstalar pacotes e apagar diretórios não ocorre implicitamente. Assim, mudar o perfil de uma máquina usada não transforma uma reaplicação em limpeza destrutiva.

## Armazenamento

Valores de `Storage.Data.SecondaryDiskPolicy`:

- `UseIfAvailable`: usa um único volume NTFS saudável em disco fixo secundário;
- `Ask`: pergunta se deve usar o único candidato seguro no modo `Interactive`;
- `Ignore`: usa a raiz configurada no volume do Windows.

`OnMultipleCandidates` permanece `Stop`. Dispositivos removíveis não participam por padrão.

`DedicatedVolumeSubdirectory = ''` usa diretamente a raiz do segundo volume, como `D:\`. Um valor relativo, como `'Dados'`, muda a raiz para `D:\Dados`. Em ambos os casos, `Storage.Paths` organiza as pastas do usuário sob `{PrimaryUser}` e mantém `Backups` e `Shared` globais.

Para um disco:

```powershell
Mode                = 'DirectoryOnSystemVolume'
SecondaryDiskPolicy = 'Ignore'
Root                = '{SystemRoot}\Dados'
```

Use [`examples/machine-one-disk.psd1`](examples/machine-one-disk.psd1) como ponto de partida.

`Storage.Integrations` associa destinos lógicos às pastas. `HyperV` aceita aplicação automática e configura os padrões suportados pelo host. Docker, Steam e Epic usam `ManualRequired`: o projeto cria a pasta, mostra o procedimento e registra a pendência, mas não edita arquivos internos desses aplicativos.

`Backup` usa uma pasta de `Storage.Paths` como staging. `SourcePathKeys` seleciona origens da árvore de dados e `UserProfileFolders` inclui pastas do perfil original em `C:\Users`; a cópia não segue junções. `IncludeSetupInventory = $true` inclui os JSONs de inventário Winget e versões conhecidas, sem copiar binários instalados. `ExternalDestination = ''` pergunta o destino no momento da exportação e `NoAutomaticDeletion = $true` impede retenção destrutiva. `RestoreTest` restaura o snapshot mais recente em uma pasta temporária, valida os hashes e, quando `KeepRestoredCopy = $false`, remove somente a cópia de teste depois do sucesso. O staging no mesmo disco é útil para organização e recuperação rápida, mas somente a exportação para outro armazenamento constitui uma cópia independente.

`MachineAudit` controla o resumo local. O padrão gera HTML e Markdown na Área de Trabalho ao final de `INSTALAR.cmd` ou `ATUALIZAR.cmd`; o nome e o diretório podem ser alterados. A auditoria é informativa e tolera recursos indisponíveis, registrando-os como tal sem tentar corrigir firmware, drivers ou criptografia.

`PlanSummary` controla a cópia legível do último plano. O padrão mantém o JSON técnico datado em `%ProgramData%\pc-setup\reports` e sobrescreve `PLANO-PC-SETUP.html` e `.md` na Área de Trabalho antes da confirmação. `Enabled`, `OutputDirectory`, `FileBaseName` e `Formats` podem ser alterados sem guardar dados secretos. Os formatos aceitos são `Html` e `Markdown`.

## Contas

Cada entrada possui `Enabled`, `Name` e `Role`. Funções válidas: `Standard` e `Administrator`.

Toda conta habilitada é reconciliada no grupo interno `Usuários` pelo SID conhecido do Windows, sem depender do idioma da instalação. Isso inclui contas administrativas: o grupo `Administradores` acrescenta privilégios, enquanto `Usuários` mantém o direito normal de logon interativo. Contas existentes desabilitadas são habilitadas quando continuam solicitadas pelo perfil.

As únicas contas Windows declaradas são `DailyUser`, `RecoveryAdmin` e `Public`. A IA não recebe uma conta Windows; ela usa o usuário Linux definido pelo ambiente `Agent`.

`Security.DemoteDailyUserAutomatically = $false` evita perder acesso administrativo antes do teste da conta de recuperação. O usuário diário só deve ser rebaixado depois que a conta administrativa configurada for validada.

Os papéis recomendados e seus limites estão documentados em [`../usuarios/README.md`](../usuarios/README.md). Os nomes presentes no perfil versionado são exemplos configuráveis, não requisitos do projeto.

`Security.HyperVAdministratorAccounts` recebe chaves de `Accounts`. O padrão contém somente `DailyUser`, permitindo que a conta diária administre o Hyper-V sem entrar no grupo Administradores do Windows.

## Agente de IA

`Agent` define o launcher e o limite de capacidades:

```powershell
Agent = @{
    Enabled        = $true
    Environment    = 'Agent'
    DefaultCommand = 'codex'
    Isolation      = 'AiJail'
    Harness = @{
        Enabled        = $true
        PackageManager = 'Npm'
        Package        = '@openai/codex'
        Version        = 'latest'
    }
    Memory = @{
        Enabled            = $true
        Repository         = 'akitaonrails/ai-memory'
        Version            = 'latest'
        Architecture       = 'x86_64'
        Sha256             = ''
        RequireAssetDigest = $true
        Client             = 'codex'
        ProjectStrategy    = 'repo-root'
        ServerUrl          = 'http://127.0.0.1:49374'
        LaunchMode         = 'Managed'
    }
    Launcher = @{
        DefaultMode   = 'Managed'
        PromptForMode = $true
        ReviewEnabled = $true
    }
    Workspace = @{
        Mode        = 'SelectedProjectOnly'
        DefaultPath = ''
    }
    Capabilities   = @{
        Network           = $true
        PersistAgentState = $true
        Docker            = $false
        SSH               = $false
        Display           = $false
        GPU               = $false
        X11               = $false
        HostSharedMemory  = $false
        TerminalPassthrough = $false
        InheritEnvironment = $false
        UpdateCheck       = $false
        Worktree          = $false
        SystemdUser       = $false
        Tailscale         = $false
        Pictures          = $false
    }
    ProjectSecrets = @{
        DenyPaths = @('.env', '.env.local', '.env.*.local', 'credentials.json', 'secrets/**')
        DenyPathExceptions = @()
        PreflightMode = 'Warn'
    }
    EnvironmentAllowList = @()
    VirtualMachine = @{
        Enabled = $false
        Name    = 'Agent'
    }
}
```

`Harness` instala o pacote no prefixo NPM do usuário Linux `agent`. `latest` busca a versão atual em cada aplicação; uma versão SemVer exata fixa o resultado. `DefaultCommand` precisa corresponder ao executável fornecido pelo pacote.

`Agent.Memory` instala a release nativa do `akitaonrails/ai-memory` no ambiente `Agent`, integra MCP e hooks ao cliente configurado e mantém o servidor em loopback. `latest` exige o digest SHA-256 publicado pela release; uma versão SemVer exata exige `Sha256` explícito. O perfil padrão usa `Client = 'codex'`, `ProjectStrategy = 'repo-root'` e `LaunchMode = 'Managed'`, evitando que mudanças para subdiretórios fragmentem a memória e permitindo continuidade por `ai-memory run`.

Perfis antigos sem a seção `Memory` continuam válidos e recebem memória desabilitada em tempo de execução. Isso preserva a compatibilidade sem ativar persistência de dados silenciosamente.

O token `AI_MEMORY_AUTH_TOKEN` do servidor não pertence ao PSD1. Ele é gerado durante o bootstrap, gravado somente em `~/.config/ai-memory/env` do usuário Linux do agente e protegido com modo `0600`. O estado fica em `~/.local/share/ai-memory`, também fora do Git. `ServerUrl` aceita somente `http://127.0.0.1:<porta>` porque este projeto não publica a memória na rede.

Ao trocar o harness, altere `DefaultCommand`, `Harness` e `Memory.Client` juntos e confirme que a release atual do `ai-memory` suporta MCP e hooks para o cliente escolhido. A validação detalhada de arquivo MCP implementada pelo perfil padrão cobre o Codex; outros clientes continuam sujeitos ao contrato do instalador oficial.

`Workspace.Mode = 'SelectedProjectOnly'` usa o diretório informado no launcher como fronteira da execução. `DefaultPath = ''` pergunta o caminho sempre; um caminho Windows ou WSL pode ser definido como padrão sem colocar credenciais no arquivo. O launcher canonicaliza o caminho e recusa raízes de sistema, homes inteiros, raízes de discos e as próprias raízes configuradas de projetos. Ele não tenta adivinhar se um subdiretório representa semanticamente um único projeto.

Se `DefaultPath` for preenchido, aponte para um projeto abaixo da raiz, por exemplo `/home/agent/Dev/meu-projeto`, e não para `/home/agent/Dev`.

A autenticação do harness e as credenciais Git não são automatizadas. Elas pertencem ao home do usuário Linux `agent` e devem ser liberadas manualmente. A VM permanece apenas como opção declarada; não há criação automática.

`RestrictedMode.Enabled = $true` exige o conjunto conservador de capacidades do perfil padrão: sem Docker, SSH, interface gráfica, ambiente herdado ou outros canais privilegiados. `Lockdown = $false` preserva projeto gravável, rede e autenticação persistente, necessários ao Codex interativo. Se `Lockdown` for ativado, o `ai-jail` passa a executar em modo estrito, somente leitura, efêmero e sem rede; esse modo é adequado a comandos locais de inspeção, não ao fluxo normal do Codex.

`Launcher.PromptForMode = $true` evita depender de memorizar comandos: `AGENTE.cmd` mostra o fluxo normal gerenciado, revisão somente leitura e compatibilidade direta. O modo de revisão ainda libera rede e o estado de login do Codex; portanto, não substitui uma VM para conteúdo hostil.

`ProjectSecrets` adiciona regras `--deny-path` em toda abertura do agente. `PreflightMode = 'Warn'` informa correspondências existentes antes da sessão. Os caminhos são relativos ao projeto escolhido e não podem apontar para fora dele. As regras alcançam somente arquivos existentes quando o sandbox é construído; encerre e reabra o agente depois de criar um novo segredo. Exceções devem ser restritas a arquivos comprovadamente não secretos.

`EnvironmentAllowList` aceita somente nomes de variáveis. O launcher repassa seus valores do ambiente local com `--env NOME`; valores e segredos continuam fora do PSD1. `InheritEnvironment` permanece desabilitado.

## Pacotes

`Packages.Profiles` seleciona arquivos de `config/packages`. Cada linha usa `ID|escopo|criticidade`, por exemplo `Google.Chrome|machine|optional` ou `Git.Git|machine|required`. Linhas antigas sem os campos usam `Packages.InstallScope` e `Packages.DefaultCriticality`.

`Packages.InstallScope` aceita `machine` ou `user`; `required` interrompe quando a versão não pode ser confirmada e `optional` deixa uma pendência para `ATUALIZAR.cmd`. Chrome, Brave, Yubico Authenticator e Proton VPN permanecem em `machine`; Bitwarden, Proton Mail, PowerShell e Windows Terminal usam `user`. A fase Winget roda na conta diária e instaladores de máquina podem solicitar UAC por conta própria.

O pacote Yubico instala somente o Authenticator. Registro da chave, PIN, passkeys, contas e códigos de recuperação não fazem parte da automação.

O fallback fica em `offline-installers.psd1`. Cada entrada exige `PackageId`, caminho relativo, SHA-256, argumentos silenciosos e `Scope` igual ao escopo configurado. O diretório padrão é `installers` na raiz do projeto.

## WSL

`DefaultVersion = 2` define o padrão global. `Distribution = ''` mantém desativado o mecanismo legado de instalação centralizada.

`WSL.Environments` descreve perfis aplicados às distribuições registradas por conta Windows. Cada entrada informa:

- `Enabled`: se o ambiente deve ser preparado;
- `AccountKey`: chave da conta em `Accounts`;
- `Distribution`: nome aceito por `wsl --install --distribution`;
- `Profile`: PSD1 relativo ao projeto com usuário Linux, raiz de projetos e pacotes APT.
- `Default`: se o perfil define o usuário padrão daquela distribuição.

O perfil padrão liga `DailyUser` e `Agent` à mesma conta Windows e à mesma distribuição. Aplique os dois na conta diária, começando por `DailyUser`; consulte [`../wsl/README.md`](../wsl/README.md).

O perfil `wsl\profiles\agent.psd1` declara usuário sem privilégios, workspace compartilhado e política de versão do `ai-jail`. A configuração de harness e memória é injetada a partir de `Agent`, evitando duas fontes de verdade. Com `Version = 'latest'`, cada aplicação resolve as releases estáveis atuais pela API do GitHub e exige o digest SHA-256 do asset. Uma versão exata continua possível, mas exige `Sha256` explícito.

## Inventário do Winget

`Runtime.StateDirectory` e `Runtime.ReportDirectory` guardam estado e relatórios elevados em `%ProgramData%`. `UserStateDirectory`, `UserReportDirectory` e `WingetInventoryPath` ficam em `%LOCALAPPDATA%` da conta diária, permitindo que a fase sem elevação registre IDs, versões, fontes e personalização. `ExecutionLogEnabled = $true` mantém um histórico JSONL sanitizado de cada reconciliação e teste integral; ele pode ser desabilitado em outro perfil sem alterar o tratamento de erros. Esses arquivos são estado local gerado e não devem ser adicionados ao repositório.

`Versions.Mode = 'Latest'` busca versões atuais. `CaptureKnownGood = $true` grava um snapshot local após Winget e WSL terminarem validados. `FIXAR-VERSOES.cmd` exporta um arquivo sem segredos para `Versions.LockFile`; com `Mode = 'Locked'`, cada pacote configurado precisa ter uma versão e o Winget recebe `--version`. O modo fixado é destinado principalmente a instalação limpa e não autoriza downgrade automático.

## Recuperação

As proteções obrigatórias não devem ser relaxadas:

```powershell
RequireRestorePointBeforeChanges = $true
AllowExistingRestorePointReuse   = $false
AllowSameApplySessionReuse       = $true
BackupAclBeforeChanges           = $true
```

A reutilização só vale para a mesma aplicação retomada depois de reinício, com descrição, sequência e identificador validados.

`UserPhaseReceiptMaxAgeHours = 24` limita por quanto tempo pacotes, personalização e WSL podem reutilizar o comprovante da fase Windows. Depois desse prazo, o fluxo gera uma nova aplicação protegida em vez de confiar indefinidamente em um ponto antigo.

## BitLocker

O padrão é somente informativo:

```powershell
ManageBitLocker       = $false
BitLockerMode         = 'DoNotConfigure'
ReportBitLockerStatus = $true
```

O setup não ativa, suspende, desativa, armazena chave de recuperação nem exige criptografia. A ativação do BitLocker e a guarda da chave devem ser feitas manualmente fora do projeto, depois da validação da máquina.

## Personalização e debloat

`Personalization.Enabled` controla o personalizador. `ApplyOnInstall = $true` o inclui na instalação e `PromptOnUpdate = $true` faz o atualizador perguntar antes de reaplicá-lo. Tema, barra de tarefas, menu Iniciar, Edge, remoções explícitas, pastas conhecidas, plano de fundo e tela de bloqueio permanecem configuráveis no mesmo bloco.

`Taskbar.Pins` define os fixados por `DesktopApplicationID`, `DesktopApplicationLinkPath` ou `AppUserModelID`. O padrão tenta substituir os atalhos do Windows pelo CSP oficial e usa `PinGeneration = 1`; você continua livre para alterar a barra. Se a build recusar o CSP por usuário, o resultado fica como `ManualRequired`, a instalação continua e o ajuste permanece manual. Ao mudar o padrão e querer fixar novamente um aplicativo já removido, incremente essa geração. `WebSearchMode = 'Supported'` usa apenas políticas documentadas; `Aggressive` acrescenta ajustes de melhor esforço para Windows 11 Pro.

O padrão usa `RedirectKnownFolders = $false` e `RestoreKnownFoldersToProfile = $true`: as pastas conhecidas permanecem no perfil Windows e, se já estiverem redirecionadas, o conteúdo é copiado de volta sem exclusão automática da origem. `ProfileLink` cria `Data` dentro da pasta de dados do usuário como uma junção para o perfil original. `GoogleDrive` registra `Storage.Paths.Drive` como ponto de montagem em modo `Streaming`; login, credenciais e seleção de conta continuam manuais. `PreserveAppxPackages` documenta os componentes que não podem entrar em `RemoveAppxPackages`; o padrão preserva Vincular ao Celular e Cross Device.

O plano de fundo é opcional e precisa estar dentro do projeto. `WallpaperPath = ''` mantém a imagem atual; um caminho relativo aplica a imagem na conta diária. `LockScreen.Mode = 'Manual'` prepara a imagem e preserva a possibilidade de trocá-la nas Configurações. Consulte [`../docs/PERSONALIZACAO.md`](../docs/PERSONALIZACAO.md).

O perfil Felipe habilita um debloat reproduzível, aplicado por `INSTALAR.cmd` e disponível separadamente em `DEBLOAT.cmd`:

```powershell
Enabled          = $true
Release          = '2026.07.11'
Preset           = 'RunDefaults'
Silent           = $true
AppRemovalTarget = 'AllUsers'
RemoveGamingApps = $false
```

O ZIP da tag exige o SHA-256 versionado. A confirmação `S` do plano da instalação autoriza a etapa; `DEBLOAT.cmd` solicita uma confirmação própria. Edge não é removido e o parâmetro de remoção de Xbox/Game Bar não é enviado.

O debloat é uma exceção intencional à política `latest`: como executa remoções e muda configurações do Windows, uma nova release só deve substituir a versão fixada depois de revisão e atualização do SHA-256.
