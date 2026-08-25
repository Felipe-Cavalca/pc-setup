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
- instala ou atualiza Chrome, Brave, Yubico Authenticator, Bitwarden, WinRAR, Google Drive, ferramentas de desenvolvimento e launchers de jogos pelo Winget, com escopo e criticidade explícitos por pacote;
- atualiza o WSL 2 e prepara, na mesma distribuição Ubuntu, os usuários Linux diário e `agent`;
- resolve as releases estáveis atuais do `ai-jail` e do `ai-memory`, exige os digests SHA-256 publicados pelo GitHub, instala/atualiza o Codex e fornece um launcher isolado com memória local;
- permite que o usuário diário administre o Hyper-V sem torná-lo administrador geral do Windows;
- gera relatórios JSON de plano, aplicação, versões instaladas pelo Winget e validação;
- registra cada instalação, atualização e teste integral em log JSONL cronológico e sanitizado;
- atualiza na Área de Trabalho uma cópia legível do plano em HTML e Markdown antes de pedir confirmação;
- registra um snapshot local das versões conhecidas como boas para uma reinstalação reproduzível;
- prepara backup local verificável, cuja cópia para outro disco é disparada manualmente;
- permite restaurar integralmente um snapshot em uma pasta temporária, validar os hashes e remover somente essa cópia de teste;
- gera na Área de Trabalho um resumo informativo em HTML e Markdown com Windows, hardware, virtualização, armazenamento, dispositivos e estado do `pc-setup`;
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
3. mostra o plano e o disco escolhido e atualiza `PLANO-PC-SETUP.html` e `PLANO-PC-SETUP.md` na Área de Trabalho;
4. pede `S` uma única vez;
5. aplica e valida as configurações de máquina em processo elevado;
6. se a conta atual não for a conta diária configurada, pede para entrar nela e executar o mesmo arquivo novamente;
7. na conta diária, aplica pacotes e personalização no perfil correto, elevando somente instaladores de máquina que precisarem;
8. aplica e valida os ambientes WSL da conta diária, primeiro o usuário padrão e depois o `agent`;
9. registra as versões realmente validadas de Winget e WSL;
10. atualiza `RESUMO-DA-MAQUINA.html` e `RESUMO-DA-MAQUINA.md` na Área de Trabalho.

Pacotes com escopo `machine` podem abrir um pedido de UAC durante a fase da conta diária. Isso é esperado: o Winget continua disponível no perfil correto, enquanto somente o instalador que precisa alterar a máquina recebe elevação.

Se for necessário reiniciar, reinicie o Windows e clique no mesmo arquivo novamente. A aplicação será retomada do ponto salvo. Em uma máquina usada, a fase administrativa pode criar a conta diária configurada; depois, entre nessa conta e clique novamente em `INSTALAR.cmd`. Se pacotes, personalização ou WSL falharem depois da conclusão do Windows, uma nova execução retoma somente as fases da conta diária, desde que configuração e projeto não tenham mudado. Senhas de contas novas ainda são solicitadas em prompt seguro.

### Atualizar ou reaplicar depois

Depois de alterar `config/machine.psd1`, os perfis ou os scripts, dê duplo clique em `ATUALIZAR.cmd`. Ele funciona como uma reconciliação idempotente:

1. planeja o Windows e os ambientes WSL habilitados para a conta diária;
2. mostra, aplica e valida o estado do Windows pelo mesmo fluxo protegido do instalador;
3. interrompe e pede reinício quando um recurso do Windows exigir;
4. reaplica e valida primeiro o usuário Linux padrão e depois o `agent`.

Esse fluxo atualiza pacotes com política de versão atual, incluindo Winget, APT, `Agent.Harness.Version = 'latest'`, `Agent.Memory.Version = 'latest'` e `AiJail.Version = 'latest'`. Ele não atualiza o próprio repositório por Git e não envia credenciais ao repositório.

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

Leia o plano mostrado e o caminho do relatório. O JSON técnico continua em `%ProgramData%\pc-setup\reports`; o perfil padrão também atualiza `PLANO-PC-SETUP.html` e `.md` na Área de Trabalho com a mesma prévia. Se a escolha do disco, usuários, recursos e programas estiver correta:

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

Quando `Runtime.ExecutionLogEnabled = $true`, o orquestrador também mostra o caminho de um arquivo `execution-*.jsonl` em `%LOCALAPPDATA%\pc-setup\reports`. Cada linha registra horário, etapa, resultado, ferramenta e argumentos seguros. Campos e argumentos reconhecidos como senha, token, credencial, chave ou PIN são substituídos por `[REDACTED]`; a transcrição bruta do terminal não é gravada.

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
VMs
Containers
Backups
```

As ACLs protegidas são:

- `Dev`: usuário principal com modificação;
- dados pessoais: somente usuário principal, SYSTEM e Administradores.
- `Backups`: somente usuário principal, SYSTEM e Administradores.

O agente não usa uma pasta Windows dedicada. Ele roda como o usuário Linux `agent`, sem `sudo`, dentro do WSL e do `ai-jail`. O workspace Linux compartilhado fica em `/home/agent/Dev`; `felipe` e `agent` pertencem ao grupo `pcsetup-agent`.

Quando a raiz de dados escolhida for `D:\`, a pasta Windows `D:\Dev` aparece no WSL como `/mnt/d/Dev`. Use-a para projetos manipulados principalmente por programas Windows. Para Git, dependências, builds e containers executados principalmente no Linux, prefira `/home/felipe/Dev` ou `/home/agent/Dev`, que oferecem melhor desempenho no WSL. Em uma máquina de um disco, o caminho Windows configurado passa a ser `C:\Dados\Dev`, acessível como `/mnt/c/Dados/Dev`.

Os nomes das contas são configuráveis. Consulte os papéis e limites de cada conta em [`usuarios/README.md`](usuarios/README.md).

Antes da alteração, o script exporta as ACLs para `%ProgramData%\pc-setup\acl-backups`. Se a própria etapa de ACL falhar, ela tenta restaurar os backups daquela etapa. Falhas posteriores não provocam rollback automático das ACLs.

Perfis do Windows, `AppData`, `ProgramData` e componentes do sistema não são movidos.

O Hyper-V recebe automaticamente `VMs` como destino padrão para novas máquinas e `VMs\Virtual Hard Disks` para novos VHDs. Docker Desktop, Steam e Epic exigem confirmação nas respectivas interfaces; o plano, a aplicação e o verificador mostram a pasta e mantêm essa pendência visível. O projeto não altera arquivos internos não documentados desses aplicativos.

## Programas

Os perfis ficam em [`config/packages`](config/packages):

- `base`: Chrome, Brave, Yubico Authenticator, Bitwarden, WinRAR e Google Drive;
- `development`: Git, PowerShell, Windows Terminal, VS Code e Docker Desktop;
- `gaming`: Steam e Epic Games Launcher.

O Winget consulta a fonte oficial configurada no Windows. Cada linha usa `ID|escopo|required/optional`. Falha em item `required` interrompe; item `optional` fica pendente para a próxima execução. Chrome, Brave e os aplicativos tradicionais usam `machine`; Bitwarden, PowerShell e Windows Terminal usam `user`. Em caso de falha, um instalador offline só é aceito quando consta em [`config/offline-installers.psd1`](config/offline-installers.psd1), declara o mesmo escopo, existe dentro da pasta permitida e tem SHA-256 idêntico ao manifesto.

O fallback offline pode estar atrás da versão publicada. O inventário registra o que foi realmente instalado e a próxima execução com acesso à internet tenta atualizar novamente.

`Yubico.Authenticator` instala somente o aplicativo. Cadastro da YubiKey, PIN, contas, passkeys e códigos de recuperação permanecem manuais; o projeto não lê nem grava segredos da chave.

Ao final da etapa, as versões realmente encontradas pelo `winget export --include-versions` são registradas em `%LOCALAPPDATA%\pc-setup\winget-installed.json` da conta diária e arquivadas junto aos relatórios da fase do usuário.

O padrão `Versions.Mode = 'Latest'` continua buscando versões atuais. Depois de uma execução completa, `%LOCALAPPDATA%\pc-setup\versions-known-good.json` reúne o inventário Winget e os manifestos WSL validados. `FIXAR-VERSOES.cmd` exporta esse estado para `config\versions.lock.json`; para reproduzi-lo em uma instalação limpa, altere `Versions.Mode` para `Locked`. O modo fixado usa `winget --version` e valida divergências, mas não desinstala nem força downgrade numa máquina já em uso.

## Backup de dados

`BACKUP.cmd` copia `PersonalData` e `Development` para um snapshot datado dentro de `Backups`, sem excluir snapshots anteriores, e cria um manifesto SHA-256. Essa cópia local é uma área de preparação e recuperação rápida, não um backup independente enquanto estiver no mesmo disco dos dados.

Com a unidade externa conectada, `EXPORTAR-BACKUP.cmd` copia o snapshot mais recente para `pc-setup-backups` no destino informado e verifica novamente os hashes. `VERIFICAR-BACKUP.cmd` confere o snapshot local mais recente. `TESTAR-RESTAURACAO.cmd` copia todo o snapshot para a pasta temporária configurada, valida o manifesto e remove somente essa cópia depois do sucesso; o snapshot nunca é apagado. `Backup.ExternalDestination` pode guardar um caminho de disco externo ou de pasta sincronizada; autenticação e credenciais continuam fora do repositório.

Se o Winget não conseguir abrir a fonte padrão ou retornar `0x80070005` ou `0x80072ee7`, siga o procedimento em [Winget sem acesso à fonte padrão](docs/RECUPERACAO.md#winget-sem-acesso-à-fonte-padrão).

## WSL e agente de IA

O bootstrap principal configura os recursos globais do WSL. Na instalação inicial, `INSTALAR.cmd` aplica dois perfis na mesma distribuição: primeiro `DailyUser`, depois `Agent`. Em manutenções posteriores, `ATUALIZAR.cmd` reconcilia os mesmos perfis. Ambos devem ser executados na conta Windows diária, e o perfil do agente não troca o usuário padrão da distribuição.

Os comandos, perfis convergentes e a decisão entre `/mnt/d/Dev` e o filesystem Linux estão em [`wsl/README.md`](wsl/README.md). Os relatórios WSL incluem as versões APT, do harness, do `ai-jail` e do `ai-memory` realmente encontradas no manifesto instalado.

O perfil padrão instala a versão atual do pacote NPM `@openai/codex` para o usuário Linux `agent`. A autenticação é feita manualmente uma vez e permanece no estado explicitamente liberado do agente. O `ai-memory` roda como o mesmo usuário, em serviço local protegido por token, registra MCP e hooks do Codex e usa a raiz Git como identidade padrão do projeto. `AGENTE.cmd` solicita o modo e um diretório, usando por padrão `ai-jail ai-memory run codex`; a opção de revisão deixa o projeto somente leitura. Antes de abrir, o preflight informa caminhos sensíveis que serão negados. Consulte o modelo de segurança, a operação da memória e as limitações em [`docs/AGENTE-IA.md`](docs/AGENTE-IA.md).

## Criar um perfil de máquina

Use `config/machine.psd1` como referência e altere, principalmente:

- `Machine.PrimaryUser`;
- nomes, funções e `Enabled` das contas Windows;
- harness, memória, workspace, capacidades e ambiente WSL do agente;
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

Cada plano válido mantém o JSON técnico datado e sobrescreve os arquivos legíveis `PLANO-PC-SETUP.html` e `.md` na Área de Trabalho, evitando acúmulo. Ambos indicam que são apenas uma prévia; nenhuma alteração é aplicada até a confirmação. Quando o lançador solicita credenciais de administrador, os arquivos continuam sendo destinados à Área de Trabalho da conta que iniciou o processo.

Depois da reconciliação, o perfil padrão cria `RESUMO-DA-MAQUINA.html` e `.md` na Área de Trabalho. `RESUMO-DA-MAQUINA.cmd` atualiza os dois arquivos sob demanda. O relatório é somente leitura e não atualiza BIOS, firmware, drivers, BitLocker, TPM ou YubiKey. Consulte [`docs/AUDITORIA-DA-MAQUINA.md`](docs/AUDITORIA-DA-MAQUINA.md).

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

Depois de uma instalação completa em VM ou máquina real, entre na conta diária e execute `TESTAR-INTEGRACAO.cmd`. Ele automatiza a suíte do projeto, solicita UAC para o `verify.ps1` somente leitura e valida os ambientes WSL aplicáveis, gerando `integration-test-*.json`. A criação da VM, os reinícios e a comprovação visual do primeiro logon continuam no roteiro manual porque não são reproduzíveis com segurança nos runners hospedados do GitHub.

Consulte também [`SECURITY.md`](SECURITY.md) para o modelo de suporte e reporte de vulnerabilidades. O mantenedor ainda precisa escolher e publicar uma licença antes de declarar permissões de reutilização.

## Referências

- [Akitando #114](https://akitaonrails.com/2022/02/15/akitando-114-o-melhor-setup-dev-com-arch-e-wsl2/)
- [System Protection](https://support.microsoft.com/en-us/windows/experience/backup-recovery/system-protection)
- [Checkpoint-Computer](https://learn.microsoft.com/pt-br/powershell/module/microsoft.powershell.management/checkpoint-computer?view=powershell-5.1)
- [Windows 11 release information](https://learn.microsoft.com/windows/release-health/windows11-release-information)
- [Arquivos entre Windows e WSL](https://learn.microsoft.com/windows/wsl/filesystems)
- [Winget export](https://learn.microsoft.com/windows/package-manager/winget/export)
- [ai-memory](https://github.com/akitaonrails/ai-memory)
- [Win11Debloat](https://github.com/Raphire/Win11Debloat)
