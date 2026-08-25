# Segurança

## Escopo suportado

O perfil padrão suporta Windows 11 Pro com `EditionID = Professional`, build 22000 ou superior e arquitetura x64. Hyper-V, Windows Sandbox e WSL dependem de virtualização habilitada e hardware compatível. Os perfis de `ai-jail` e `ai-memory` publicados neste repositório usam Linux x86_64.

O projeto executa etapas administrativas e baixa software de terceiros. Revise `config/machine.psd1`, o plano gerado e os IDs de pacote antes de aplicar. Teste alterações em VM.

## Modelo de confiança

- configuração versionada não contém segredos;
- Winget usa a fonte configurada no Windows e escopo explícito;
- instaladores offline exigem caminho permitido, escopo e SHA-256 revisado;
- `ai-jail` em política `latest` exige o digest SHA-256 publicado pela API de releases do GitHub;
- `ai-memory` em política `latest` exige o digest SHA-256 publicado, escuta somente em `127.0.0.1` e usa um token gerado localmente;
- debloat permanece fixado por tag e SHA-256 e exige confirmação no plano da instalação ou no launcher independente;
- o usuário Linux `agent` não recebe senha utilizável, sudo, Docker ou LXD;
- uma VM descartável continua obrigatória para malware ou código deliberadamente hostil.

Um hash confirma integridade do arquivo obtido, mas não substitui confiança no fornecedor, na conta do projeto ou na infraestrutura de distribuição.

## Memória e dados sensíveis

Não abra issue, commit ou relatório público contendo senhas, tokens, cookies, chaves, `.env`, arquivos exportados do WSL ou discos de VM. Relatórios locais podem conter nomes de usuários, caminhos, programas e informações do hardware.

O `ai-memory` pode registrar prompts, respostas, eventos de ferramentas e resumos. As regras de negação do `ai-jail` reduzem o acesso direto a arquivos conhecidos, mas não removem um segredo que tenha sido colado no prompt ou apareça na saída de uma ferramenta. Trate `~/.local/share/ai-memory`, `~/.config/ai-memory/env`, a configuração do cliente e qualquer exportação da distribuição WSL como dados sensíveis.

O preflight do launcher apenas avisa sobre caminhos sensíveis existentes e aplica as negações antes da sessão. Um arquivo criado depois da abertura ainda pode ser lido; encerre e reabra o agente depois de criar segredos. A lista de ambiente aceita nomes de variáveis, mas seus valores ficam legíveis para os processos dentro do sandbox quando forem explicitamente liberados.

O modo de revisão deixa o projeto somente leitura, mas mantém rede e credenciais do Codex. Ele protege contra escrita acidental, não contra exfiltração por código hostil. Para esse caso, use uma VM descartável sem credenciais reutilizadas.

Memória de agente é contexto histórico, não fonte de verdade. Código, testes, documentação revisada e estado observado da máquina continuam tendo precedência sobre recordações geradas ou consolidadas por IA.

## Reportar uma vulnerabilidade

Não publique detalhes exploráveis antes de existir uma correção. Use o recurso privado de aviso de segurança do GitHub, quando disponível, ou contate o mantenedor pelos canais indicados no perfil do repositório. Inclua versão, configuração mínima para reproduzir, impacto e evidências sem credenciais reais.

## Atualizações

Execute `ATUALIZAR.cmd` para reconciliar versões atuais. Mudanças em isolamento, privilégios, downloads, ACLs, recuperação ou elevação devem passar pela suíte automatizada e pelo roteiro de VM antes de uso em hardware real.
