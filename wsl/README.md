# Ambientes WSL

O bootstrap principal habilita os recursos do Windows, atualiza o WSL e define a versão 2 como padrão. A distribuição Linux é configurada depois, sem elevação, na sessão da conta Windows diária.

O perfil padrão usa uma única distribuição `Ubuntu-24.04`, registrada para `Felipe`, com dois usuários Linux:

- `felipe`: usuário padrão da distribuição e ambiente de desenvolvimento manual;
- `agent`: usuário sem `sudo` e com senha bloqueada, usado exclusivamente pelas IAs.

Isso evita uma segunda instalação completa do Ubuntu. O isolamento da IA vem do `ai-jail`; o usuário Linux separado mantém home, caches e autenticação fora do perfil `felipe`.

## Aplicar

Na instalação inicial, o caminho recomendado é executar `INSTALAR.cmd` na conta Windows diária. Ele configura o Windows e, após a mesma confirmação, aplica e valida automaticamente os ambientes habilitados na ordem correta. Use `ATUALIZAR.cmd` nas reconciliações posteriores.

Se pacotes, personalização ou WSL falharem depois que o Windows já tiver sido concluído e validado, execute novamente o mesmo arquivo. O orquestrador retoma as fases da conta diária quando encontra um relatório Windows concluído com os mesmos hashes de configuração e projeto.

Para aplicar manualmente, depois que o bootstrap principal terminar e o Windows tiver sido reiniciado, abra o Windows PowerShell 5.1 sem elevação na raiz do projeto.

Aplique primeiro o perfil diário:

```powershell
.\wsl\bootstrap.ps1 -Environment DailyUser -Plan
.\wsl\bootstrap.ps1 -Environment DailyUser -Apply
.\wsl\verify.ps1 -Environment DailyUser
```

Depois aplique o perfil do agente:

```powershell
.\wsl\bootstrap.ps1 -Environment Agent -Plan
.\wsl\bootstrap.ps1 -Environment Agent -Apply
.\wsl\verify.ps1 -Environment Agent
```

O segundo perfil reutiliza a distribuição, cria `agent`, bloqueia sua senha, remove participação em `sudo`, `wheel`, `docker` ou `lxd`, recusa regras diretas em sudoers, cria o workspace compartilhado e instala o harness configurado. No padrão, são usadas as versões estáveis atuais do `ai-jail` e de `@openai/codex`; ele não muda o usuário padrão do Ubuntu.

O bootstrap é idempotente. As versões dos pacotes APT, do harness e a política solicitada ficam em `/var/lib/pc-setup/<ambiente>/installed.tsv`; os relatórios PowerShell ficam em `%LOCALAPPDATA%\pc-setup\reports`.

## Executar uma IA

`AGENTE.cmd` pode ser aberto pela conta Windows diária. Ele solicita o caminho de um projeto e executa `Agent.DefaultCommand` como o usuário Linux `agent`, dentro do `ai-jail`. Com `Workspace.DefaultPath = ''`, essa escolha ocorre em toda execução.

O perfil padrão:

- libera rede e o estado de autenticação específico do agente;
- mantém Docker, SSH, interface gráfica, GPU, X11, memória compartilhada do host, Tailscale, Pictures, barramento `systemd --user`, ambiente herdado e terminal bruto bloqueados;
- mantém home privado, Landlock, seccomp e limites de recursos habilitados;
- recusa raízes de sistema, a raiz de um disco montado, homes inteiros, raízes configuradas de projetos e caminhos não canônicos;
- libera escrita somente no projeto escolhido pelo `ai-jail`.

O bootstrap instala ou atualiza o harness configurado. O comando padrão é `codex`; pacote, versão e comando podem ser trocados juntos em `Agent.Harness` e `Agent.DefaultCommand`.

No primeiro `AGENTE.cmd`, faça a autenticação interativa do Codex quando solicitada. `PersistAgentState = $true` mantém essa sessão no home de `agent`; o setup não recebe nem grava a credencial no repositório. Credenciais Git também permanecem ausentes até serem configuradas manualmente para esse usuário Linux.

Para executar manualmente outro comando instalado:

```powershell
.\scripts\Start-Agent.ps1 -ProjectPath D:\Dev\projeto -Command claude
```

## Onde guardar projetos

Use o filesystem Linux, como `/home/felipe/Dev` ou `/home/agent/Dev`, quando Git, gerenciadores de pacotes, builds e containers forem executados principalmente no Linux. É a opção de melhor desempenho para árvores com muitos arquivos pequenos.

O workspace do agente pode ser aberto no Explorer por:

```text
\\wsl$\Ubuntu-24.04\home\agent\Dev
```

Use `/mnt/d/Dev` quando o mesmo checkout precisar ser manipulado principalmente por programas Windows. Essa integração é conveniente, mas costuma ser mais lenta para builds Linux e pode expor diferenças de permissões e finais de linha.

Evite alternar ferramentas Windows e Linux sobre o mesmo checkout. Para projetos grandes, prefira clones ou worktrees separados.

## Configuração

`config\machine.psd1` associa os dois ambientes à mesma conta e distribuição:

```powershell
WSL = @{
    Environments = @{
        DailyUser = @{
            AccountKey   = 'DailyUser'
            Distribution = 'Ubuntu-24.04'
            Profile      = 'wsl\profiles\daily-user.psd1'
            Default      = $true
        }
        Agent = @{
            AccountKey   = 'DailyUser'
            Distribution = 'Ubuntu-24.04'
            Profile      = 'wsl\profiles\agent.psd1'
            Default      = $false
        }
    }
}
```

O perfil `agent.psd1` usa `Version = 'latest'`: a aplicação consulta a release estável atual pela API oficial do GitHub, seleciona o asset x86_64, exige o digest SHA-256 publicado, verifica o arquivo e registra versão, hash do arquivo e hash do binário instalado. Uma versão SemVer exata com SHA-256 explícito também é aceita. ARM64 ainda não é suportado pelo perfil versionado; esse trabalho permanece registrado na [issue #2](https://github.com/Felipe-Cavalca/pc-setup/issues/2).

## Limite do isolamento

`ai-jail` é um sandbox de processo. Ele reduz o acesso ao filesystem e às capacidades do host, mas não equivale a uma VM com outro kernel. Para código hostil ou desconhecido, use uma VM descartável. Nenhuma VM é criada por padrão.

Consulte também [`../docs/AGENTE-IA.md`](../docs/AGENTE-IA.md).

## Referências

- [ai-jail](https://github.com/akitaonrails/ai-jail)
- [Codex CLI](https://github.com/openai/codex)
- [Instalar e atualizar o Codex CLI](https://help.openai.com/en/articles/11096431)
- [Arquivos entre Windows e WSL](https://learn.microsoft.com/windows/wsl/filesystems)
- [Comandos básicos do WSL](https://learn.microsoft.com/windows/wsl/basic-commands)
