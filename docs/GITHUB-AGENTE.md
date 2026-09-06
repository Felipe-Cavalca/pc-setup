# GitHub no agente isolado

O `pc-setup` permite que o Codex use uma conta GitHub dedicada sem liberar o restante do home Linux nem remover o `ai-jail`.

## Como funciona

O ambiente Linux `agent` instala o GitHub CLI (`gh`). A autenticação é feita manualmente uma vez, fora da jaula:

```powershell
wsl -d Ubuntu-24.04 -u agent
```

No Ubuntu:

```bash
gh auth login --hostname github.com --git-protocol https --web
gh auth status
gh api user --jq .login
```

O login fica em `/home/agent/.config/gh`.

Ao abrir `AGENTE.cmd` ou `agente`, `Start-AgentWithGitHub.ps1` verifica se esse login existe. Quando existe, o launcher acrescenta ao `ai-jail` somente:

- `/home/agent/.config/gh` em leitura;
- configuração efêmera do Git para usar `gh auth git-credential` somente em `github.com`.

O token não é extraído pelo `pc-setup`, não entra em `machine.psd1` e não é copiado para o repositório.

## Capacidades resultantes

Dentro do agente, passam a funcionar comandos como:

```bash
gh auth status
gh repo view
gh repo edit --enable-wiki=false
gh api ...
gh pr create
git push
```

A conta GitHub continua sendo a fronteira de autorização. Dê a ela acesso somente aos repositórios e organizações necessários.

## Segurança

- o usuário Linux `agent` continua sem `sudo`;
- o `ai-jail` continua usando home privado;
- o diretório do GitHub CLI entra somente em leitura;
- nenhum diretório pessoal do usuário Windows é liberado;
- o modo Review/lockdown não recebe a identidade GitHub;
- Git HTTPS usa configuração de credential helper apenas no processo isolado;
- a rede continua sendo necessária para Codex e GitHub.

A credencial GitHub continua sendo sensível: qualquer processo autorizado dentro da jaula pode usar a conta dentro do escopo concedido a ela. Use uma conta dedicada e privilégios mínimos.
