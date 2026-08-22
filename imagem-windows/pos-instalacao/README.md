# O que executar no computador

O único ponto de entrada normal é o `INSTALAR.cmd` na raiz do repositório.

Antes do duplo clique:

1. termine Windows Update e drivers;
2. habilite a Proteção do Sistema no volume do Windows;
3. revise `config\machine.psd1` — ele contém o perfil padrão da máquina do Felipe;
4. em outro computador, ajuste usuários, armazenamento, recursos e pacotes no arquivo de configuração.

Ao executar, você verá:

1. pedido de permissão de Administrador;
2. resumo do perfil e da raiz de dados escolhida;
3. plano completo, sem alterações;
4. pedido para digitar `S`;
5. criação e validação do ponto de restauração;
6. aplicação por etapas;
7. solicitação de reinício, quando necessária;
8. relatório final com `PASS`, `WARN`, `FAIL` e `INFO`.

Após um reinício, clique no mesmo `INSTALAR.cmd`. O estado salvo em `%ProgramData%\pc-setup` permite continuar do ponto correto.

Não execute os scripts numerados diretamente, exceto para diagnóstico consciente. O bootstrap protege a ordem das etapas, o plano aprovado, o ponto de restauração, o estado de retomada e os relatórios.

Senhas de contas novas aparecem somente em prompt seguro e não são salvas no repositório. O perfil padrão não configura BitLocker nem executa debloat.
