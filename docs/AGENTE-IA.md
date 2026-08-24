# Agente de IA isolado

O projeto adota o princípio de autonomia com limites: o agente recebe acesso suficiente para trabalhar em um projeto, sem receber acesso administrativo ao Windows nem acesso amplo aos arquivos pessoais.

## Arquitetura padrão

```text
usuário Windows diário
└── WSL 2 / Ubuntu
    ├── usuário Linux diário
    └── usuário Linux agent, sem sudo
        ├── ai-jail
        │   └── projeto escolhido
        └── ai-memory em 127.0.0.1
            └── estado local do agente
```

Não é criada uma conta Windows para a IA. Isso evita troca de sessão, uma segunda distribuição WSL e mecanismos para armazenar a senha de outra conta. A separação ocorre no Linux e no sandbox.

O usuário diário pode chamar o agente e acessar `/home/agent/Dev`. Somente esse workspace é compartilhado pelo grupo Linux `pcsetup-agent`; o home e os dados pessoais do usuário diário não são compartilhados por esse mecanismo.

O projeto selecionado em `AGENTE.cmd` é a unidade de permissão. O `ai-jail` recebe esse diretório, não a raiz de `D:\Dev`, `/mnt/d` ou um home inteiro. `Agent.Workspace.DefaultPath` pode preencher a escolha, mas não amplia o acesso.

O `ai-memory` roda fora do sandbox, como serviço Linux do usuário `agent`, mas não recebe o projeto como diretório de trabalho nem privilégios administrativos. Ele escuta somente no loopback, exige token e grava apenas em `~/.local/share/ai-memory`. O launcher libera esse diretório em escrita dentro do `ai-jail` para logs e fila durável dos hooks.

## Harness e credenciais

O padrão instala `@openai/codex@latest` no prefixo NPM do usuário `agent`. `ATUALIZAR.cmd` reaplica essa política e o verificador compara a versão instalada com o manifesto local.

O login do Codex é manual no primeiro uso e pode persistir porque `PersistAgentState` está habilitado. Credenciais Git não são provisionadas; quando forem necessárias, devem ser configuradas diretamente para `agent`, com o menor escopo possível. Nenhum token, cookie ou chave entra em `machine.psd1`.

O bootstrap instala MCP e hooks do `ai-memory` no mesmo home. O token do serviço é gerado na máquina e permanece em `~/.config/ai-memory/env`; ele não é mostrado no plano, gravado nos relatórios nem versionado. O padrão `repo-root` agrupa subdiretórios e worktrees pela raiz Git do projeto.

O token local autentica o cliente no serviço; ele não é credencial de provedor de IA. O setup não configura provedor, chave de API nem OAuth para consolidação. Qualquer provedor opcional deve ser liberado manualmente no mesmo perfil `agent`, depois de revisar custo e escopo.

## Capacidades

As capacidades são declaradas em `Agent.Capabilities`:

| Configuração | Padrão | Impacto |
|---|---:|---|
| `Network` | habilitada | necessária para agentes remotos; permite exfiltrar qualquer arquivo legível pelo sandbox |
| `PersistAgentState` | habilitada | mantém login e configuração do harness no home de `agent` |
| `Docker` | desabilitada | o socket do Docker equivale a acesso root ao host Linux |
| `SSH` | desabilitada | não compartilha chaves nem agente SSH |
| `Display` e `X11` | desabilitadas | não expõem a sessão gráfica, teclado ou captura de tela |
| `GPU` | desabilitada | não expõe dispositivos gráficos do host |
| `HostSharedMemory` | desabilitada | não compartilha `/dev/shm` com processos do host |
| `TerminalPassthrough` | desabilitada | mantém a filtragem do terminal |
| `InheritEnvironment` | desabilitada | não copia indiscriminadamente variáveis e segredos do shell |
| `Worktree` | desabilitada | só deve ser habilitada quando o projeto usa um Git worktree vinculado |
| `UpdateCheck` | desabilitada | atualizações permanecem centralizadas no `ATUALIZAR.cmd` |
| `SystemdUser`, `Tailscale` e `Pictures` | desabilitadas | não expõem serviços, sockets ou imagens do usuário |

O launcher passa opções explícitas ao `ai-jail`, usa home privado, mantém Landlock, seccomp e limites de recursos e impede gravação automática de configuração pelo launcher. Além do projeto e do estado do harness, somente o diretório de dados do `ai-memory` recebe escrita explícita. Um arquivo `.ai-jail` versionado no projeto deve ser revisado como código, pois pode acrescentar regras e exceções à política.

O caminho escolhido é canonicalizado e tratado como fronteira de confiança. O launcher bloqueia raízes amplas conhecidas, mas não consegue determinar se todo subdiretório representa semanticamente um único projeto. Se o usuário selecionar uma pasta ampla, todo o conteúdo legível nela poderá ser usado pelo agente.

O launcher nega por padrão os caminhos listados em `Agent.ProjectSecrets`, incluindo `.env`, arquivos locais de ambiente, `credentials.json` e `secrets/**`. As regras só alcançam arquivos correspondentes no momento da abertura. Cada repositório ainda deve usar `.gitignore` e pode acrescentar uma configuração `.ai-jail` revisada para certificados, credenciais ou exceções específicas.

O conteúdo registrado pela memória também precisa ser tratado como dado sensível e potencialmente incorreto. Um segredo colado no prompt ou devolvido por uma ferramenta pode chegar aos eventos mesmo que seu arquivo esteja bloqueado. Memória histórica ajuda a retomar contexto, mas código, testes e documentação revisada continuam sendo a fonte de verdade.

## Operação da memória

O setup inicia e valida o serviço automaticamente. Dentro do ambiente `agent`, os comandos úteis são:

```bash
ai-memory status --json
ai-memory finalize-session
```

O Codex não oferece um evento confiável de fim real da sessão. Execute `finalize-session` ao encerrar um trabalho quando quiser produzir imediatamente o resumo final, o handoff e a consolidação elegível. Não há finalização automática porque duas sessões simultâneas no mesmo projeto poderiam ser confundidas.

Para aquecer a memória de um repositório existente, revise primeiro o que seria coletado:

```bash
cd /caminho/do/projeto
ai-memory bootstrap --dry-run
```

O bootstrap real não faz parte de `INSTALAR.cmd` nem de `ATUALIZAR.cmd`: ele pode chamar um provedor pago e gerar páginas inferidas que exigem revisão.

## Git e recuperação

O agente pode modificar o projeto selecionado. Use commits pequenos, revise `git status`, `git diff` e `git diff --cached`, e mantenha cópia remota ou backup. Sandbox não substitui versionamento nem backup.

Push, SSH e Docker permanecem fora do fluxo padrão. Eles só devem ser habilitados quando o projeto exigir e depois de compreender o alcance da permissão.

## Atualizações do isolamento

O perfil do agente usa a política `latest` para `ai-jail` e `ai-memory`. `INSTALAR.cmd` e `ATUALIZAR.cmd` resolvem as releases estáveis atuais pela API oficial do GitHub e exigem o digest SHA-256 publicado para cada asset. O manifesto local registra versão resolvida, hash do arquivo e hash do binário instalado. Se a API, o digest ou a verificação falhar, o binário correspondente não é substituído.

## VM opcional

`Agent.VirtualMachine.Enabled` reserva uma escolha de configuração, mas o projeto não cria nem inicia uma VM automaticamente. Uma VM descartável é indicada para malware, instaladores desconhecidos ou código deliberadamente hostil.

O usuário diário pode ser incluído em `Hyper-V Administrators` por `Security.HyperVAdministratorAccounts`. Esse grupo permite administrar todas as VMs e switches locais; não deve incluir `agent` nem a conta pública.

## O que não entra no repositório

- tokens e chaves de API;
- cookies e sessões do harness;
- senhas;
- chaves SSH;
- arquivos `.env` reais;
- discos de VM, token do `ai-memory` e dados gerados pelo agente.

## Referências

- [ai-jail](https://github.com/akitaonrails/ai-jail)
- [ai-memory](https://github.com/akitaonrails/ai-memory)
- [Instalação e integração do ai-memory](https://github.com/akitaonrails/ai-memory/blob/main/docs/install.md)
- [Codex CLI](https://github.com/openai/codex)
- [Autonomia com cerca, por Fabio Akita](https://akitaonrails.com/2026/05/24/dicas-e-toolkit-de-ia-do-akita-ai-jail-ai-memory-ai-usagebar/)
- [Gerenciar hosts Hyper-V](https://learn.microsoft.com/windows-server/virtualization/hyper-v/manage/remotely-manage-hyper-v-hosts)
