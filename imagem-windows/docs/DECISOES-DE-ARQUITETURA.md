# Decisões de arquitetura da mídia

## Contexto

Uma implementação anterior concentrava scripts, downloads e configurações dentro de `autounattend.xml`. Essa abordagem pode executar ações durante `specialize`, antes de a rede e o ambiente de usuário estarem disponíveis.

Falhas nessa fase são difíceis de recuperar: um download incompleto impede a instalação do aplicativo, a personalização pode não ser aplicada e o resultado fica distribuído entre logs do Windows Setup.

## Decisão

A mídia é responsável somente por instalar o Windows. A pós-instalação pertence ao `pc-setup`, executado depois do primeiro login.

O arquivo de resposta é ausente por padrão. O modelo opcional do repositório configura somente idioma, região e teclado em português do Brasil.

## Regras da mídia

O `autounattend.xml` aceito pelo validador não pode conter:

- seleção de edição, imagem, disco ou partição;
- chave de produto, senha, conta ou logon automático;
- comandos em `specialize` ou `oobeSystem`;
- scripts ou arquivos embutidos;
- instalação de programas;
- alteração de BitLocker, recursos opcionais ou políticas do Windows.

## Responsabilidades do pós-instalação

O `pc-setup` concentra:

- plano revisável antes da aplicação;
- configuração específica de cada máquina;
- criação de ponto de restauração obrigatório;
- habilitação de recursos opcionais;
- instalação online pelo Winget e fallback offline validado por SHA-256;
- usuários, diretórios e permissões;
- retomada depois de reinício;
- relatórios e validação final.

## Consequências

- a mesma mídia pode ser usada em máquinas diferentes;
- decisões destrutivas permanecem nas telas do Windows Setup;
- falhas de rede não comprometem a instalação do sistema;
- mudanças pós-instalação ficam registradas e podem ser validadas;
- configuração e segredos permanecem separados.
