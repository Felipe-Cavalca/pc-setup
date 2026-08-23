# Segurança

## Escopo suportado

O perfil padrão suporta Windows 11 Pro com `EditionID = Professional`, build 22000 ou superior e arquitetura x64. Hyper-V, Windows Sandbox e WSL dependem de virtualização habilitada e hardware compatível. O perfil do `ai-jail` publicado neste repositório suporta somente Linux x86_64.

O projeto executa etapas administrativas e baixa software de terceiros. Revise `config/machine.psd1`, o plano gerado e os IDs de pacote antes de aplicar. Teste alterações em VM.

## Modelo de confiança

- configuração versionada não contém segredos;
- Winget usa a fonte configurada no Windows e escopo explícito;
- instaladores offline exigem caminho permitido, escopo e SHA-256 revisado;
- `ai-jail` em política `latest` exige o digest SHA-256 publicado pela API de releases do GitHub;
- debloat permanece fixado por tag e SHA-256 e exige confirmação separada;
- o usuário Linux `agent` não recebe senha utilizável, sudo, Docker ou LXD;
- uma VM descartável continua obrigatória para malware ou código deliberadamente hostil.

Um hash confirma integridade do arquivo obtido, mas não substitui confiança no fornecedor, na conta do projeto ou na infraestrutura de distribuição.

## Dados sensíveis

Não abra issue, commit ou relatório público contendo senhas, tokens, cookies, chaves, `.env`, arquivos exportados do WSL ou discos de VM. Relatórios locais podem conter nomes de usuários, caminhos, programas e informações do hardware.

## Reportar uma vulnerabilidade

Não publique detalhes exploráveis antes de existir uma correção. Use o recurso privado de aviso de segurança do GitHub, quando disponível, ou contate o mantenedor pelos canais indicados no perfil do repositório. Inclua versão, configuração mínima para reproduzir, impacto e evidências sem credenciais reais.

## Atualizações

Execute `ATUALIZAR.cmd` para reconciliar versões atuais. Mudanças em isolamento, privilégios, downloads, ACLs, recuperação ou elevação devem passar pela suíte automatizada e pelo roteiro de VM antes de uso em hardware real.
