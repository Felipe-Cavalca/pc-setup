# Configuração

`machine.psd1` guarda decisões não secretas e funciona como perfil versionado de referência. Ele não deve ser executado sem revisão. Os scripts não dependem de letra, modelo ou tamanho fixo de disco.

Nunca coloque no arquivo senhas, tokens, chaves de produto, certificados ou chaves de recuperação.

`INSTALAR.cmd` e `ATUALIZAR.cmd` carregam `config\machine.psd1` e usam o mesmo orquestrador de Windows e WSL. Um perfil diferente pode ser usado de duas formas:

- revisar e substituir o conteúdo de `machine.psd1` em um fork próprio;
- executar manualmente `bootstrap.ps1 -Config <arquivo>` para selecionar outro `.psd1`.

Para outro perfil no fluxo completo, execute `scripts\Start-PcSetupUpdate.ps1 -Config <arquivo>`. Use `-LauncherName INSTALAR.cmd` para uma instalação inicial ou mantenha o padrão `ATUALIZAR.cmd` para uma reconciliação posterior.

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

Para um disco:

```powershell
Mode                = 'DirectoryOnSystemVolume'
SecondaryDiskPolicy = 'Ignore'
Root                = '{SystemRoot}\Dados'
```

Use [`examples/machine-one-disk.psd1`](examples/machine-one-disk.psd1) como ponto de partida.

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
    }
    VirtualMachine = @{
        Enabled = $false
        Name    = 'Agent'
    }
}
```

`Harness` instala o pacote no prefixo NPM do usuário Linux `agent`. `latest` busca a versão atual em cada aplicação; uma versão SemVer exata fixa o resultado. `DefaultCommand` precisa corresponder ao executável fornecido pelo pacote.

`Workspace.Mode = 'SelectedProjectOnly'` usa o diretório informado no launcher como fronteira da execução. `DefaultPath = ''` pergunta o caminho sempre; um caminho Windows ou WSL pode ser definido como padrão sem colocar credenciais no arquivo. O launcher canonicaliza o caminho e recusa raízes de sistema, homes inteiros, raízes de discos e as próprias raízes configuradas de projetos. Ele não tenta adivinhar se um subdiretório representa semanticamente um único projeto.

Se `DefaultPath` for preenchido, aponte para um projeto abaixo da raiz, por exemplo `/home/agent/Dev/meu-projeto`, e não para `/home/agent/Dev`.

A autenticação do harness e as credenciais Git não são automatizadas. Elas pertencem ao home do usuário Linux `agent` e devem ser liberadas manualmente. A VM permanece apenas como opção declarada; não há criação automática.

`ProjectSecrets` adiciona regras `--deny-path` em toda abertura do agente. Os caminhos são relativos ao projeto escolhido e não podem apontar para fora dele. Se a seção estiver ausente em um perfil antigo, o carregador aplica em memória a lista segura mostrada acima. Exceções são possíveis em `DenyPathExceptions`, mas devem ser restritas a arquivos comprovadamente não secretos. Uma configuração `.ai-jail` versionada no próprio projeto pode acrescentar proteções específicas.

## Pacotes

`Packages.Profiles` seleciona arquivos de `config/packages`. Cada linha usa `ID|escopo`, por exemplo `Google.Chrome|machine` ou `Microsoft.WindowsTerminal|user`. Uma linha somente com o ID usa `Packages.InstallScope` como padrão.

`Packages.InstallScope` aceita `machine` ou `user`; o perfil padrão usa `machine`, mas cada pacote pode sobrescrever o valor. Chrome permanece em `machine` para ficar disponível às contas locais. Bitwarden e Windows Terminal usam `user`. A fase Winget roda na conta diária e instaladores de máquina podem solicitar UAC.

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

O perfil `wsl\profiles\agent.psd1` declara usuário sem privilégios, workspace compartilhado e política de versão do `ai-jail`. Com `Version = 'latest'`, cada aplicação resolve a release estável atual pela API do GitHub e exige o digest SHA-256 do asset. Uma versão exata continua possível, mas exige `Sha256` explícito.

## Inventário do Winget

`Runtime.StateDirectory` e `Runtime.ReportDirectory` guardam estado e relatórios elevados em `%ProgramData%`. `UserStateDirectory`, `UserReportDirectory` e `WingetInventoryPath` ficam em `%LOCALAPPDATA%` da conta diária, permitindo que a fase sem elevação registre IDs, versões, fontes e personalização. Esses arquivos são estado local gerado e não devem ser adicionados ao repositório.

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

O setup não ativa, suspende, desativa nem exige criptografia.

## Personalização e debloat

O plano de fundo começa desabilitado e precisa estar dentro do projeto. Ele é aplicado sem elevação na sessão da conta diária, depois que o relatório da fase Windows comprova um ponto de restauração válido.

O perfil Felipe habilita um debloat separado e reproduzível:

```powershell
Enabled          = $true
Release          = '2026.07.11'
Preset           = 'RunDefaults'
Silent           = $true
AppRemovalTarget = 'AllUsers'
RemoveGamingApps = $false
```

O ZIP da tag exige o SHA-256 versionado e a aplicação exige `-ConfirmReviewed`. Edge não é removido e o parâmetro de remoção de Xbox/Game Bar não é enviado.

O debloat é uma exceção intencional à política `latest`: como executa remoções e muda configurações do Windows, uma nova release só deve substituir a versão fixada depois de revisão e atualização do SHA-256.
