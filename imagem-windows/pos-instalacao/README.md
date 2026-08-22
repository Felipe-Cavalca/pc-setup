# Execução no Windows instalado

O único ponto de entrada normal é o `INSTALAR.cmd` na raiz do repositório.

## Pré-requisitos

1. concluir Windows Update e drivers;
2. habilitar a Proteção do Sistema no volume do Windows;
3. revisar usuários, armazenamento, recursos e pacotes em `config\machine.psd1`;
4. confirmar que o perfil corresponde à máquina antes de executar qualquer aplicação.

## Comportamento do launcher

A execução apresenta:

1. pedido de permissão de Administrador;
2. resumo do perfil e da raiz de dados escolhida;
3. plano completo, sem alterações;
4. pedido para digitar `S`;
5. criação e validação do ponto de restauração;
6. aplicação por etapas;
7. solicitação de reinício, quando necessária;
8. relatório final com `PASS`, `WARN`, `FAIL` e `INFO`.

Após um reinício, o mesmo `INSTALAR.cmd` deve ser executado novamente. O estado salvo em `%ProgramData%\pc-setup` permite continuar do ponto correto.

Os scripts numerados não são pontos de entrada de uso normal. O bootstrap protege a ordem das etapas, o plano aprovado, o ponto de restauração, o estado de retomada e os relatórios.

Senhas de contas novas aparecem somente em prompt seguro e não são salvas no repositório. O perfil padrão não configura BitLocker nem executa debloat.
