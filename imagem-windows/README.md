# Instalação do Windows e pós-instalação

Este diretório é a fonte de verdade para instalar o Windows e depois configurar o computador com o `pc-setup`.

## Decisão adotada

A mídia instala somente o Windows. Ela não instala programas, não cria usuários, não habilita recursos opcionais, não altera o BitLocker, não aplica debloat e não baixa plano de fundo.

Essa separação evita downloads em uma fase na qual a rede pode não estar pronta e mantém as alterações visíveis no plano do `pc-setup`. Também permite usar a mesma mídia no computador do Felipe, do tio, do irmão ou em uma máquina com apenas um disco.

## O que mudar na mídia atual

Não é necessário reconstruir a ISO nem alterar `boot.wim` ou `install.wim`.

Na raiz do pendrive de instalação:

1. remova o `autounattend.xml` antigo;
2. remova a pasta `Installers` antiga;
3. substitua os validadores antigos pelos arquivos de [`midia`](midia);
4. execute `Validar-Midia.cmd` e confirme `Resultado: OK`.

O modo recomendado é não colocar nenhum `autounattend.xml` na raiz. Assim, o instalador mantém as telas padrão de idioma, edição, chave, disco, partições e configuração inicial.

Se quiser apenas deixar o idioma em português do Brasil, copie [`midia/autounattend.pt-BR.opcional.xml`](midia/autounattend.pt-BR.opcional.xml) para a raiz do pendrive com o nome exato `autounattend.xml`. Essa opção não contém chave, senha, seleção de disco, conta ou script. A presença do arquivo faz o Windows Setup omitir a tela inicial de idioma; as demais escolhas continuam manuais.

Estrutura recomendada da raiz do pendrive:

```text
boot\
efi\
sources\
setup.exe
Validar-Midia.cmd
Validar-Midia.ps1
```

Estrutura opcional com idioma pré-definido:

```text
autounattend.xml
boot\
efi\
sources\
setup.exe
Validar-Midia.cmd
Validar-Midia.ps1
```

## O que você verá na instalação

No modo recomendado, o instalador permanece padrão. Escolha:

1. Windows 11 Pro;
2. instalação personalizada;
3. o disco e as partições desejadas;
4. região, teclado, rede e conta durante o OOBE.

Nenhum disco é selecionado ou apagado pelo projeto. Revise com atenção capacidade e modelo antes de excluir partições.

## O que rodar no computador novo

Depois de chegar à Área de Trabalho:

1. conclua o Windows Update e instale os drivers;
2. confirme ativação, rede, áudio e ausência de erros no Gerenciador de Dispositivos;
3. habilite manualmente a Proteção do Sistema no volume do Windows;
4. copie ou clone este repositório;
5. revise `config\machine.psd1`;
6. dê duplo clique em `INSTALAR.cmd` e aceite o UAC;
7. confira o plano e confirme somente se disco, usuários, recursos e programas estiverem corretos.

Se o script solicitar reinício, reinicie e clique em `INSTALAR.cmd` novamente. Ele retoma a aplicação e executa a validação final. Os detalhes estão em [`pos-instalacao/README.md`](pos-instalacao/README.md).

## Outra máquina

O arquivo `config\machine.psd1` é o perfil padrão da máquina do Felipe. Antes de usar em outro computador, altere pelo menos:

- `Machine.PrimaryUser`;
- contas habilitadas e seus nomes;
- `Storage.Data.SecondaryDiskPolicy`;
- recursos opcionais;
- perfis de programas.

Em uma máquina com um disco, o perfil adaptativo usa `Dados` no volume do Windows. Também existe o exemplo `config\examples\machine-one-disk.psd1`.

Configurações podem ficar no Git; senhas, tokens, chaves, instaladores e dados pessoais não.

## Validação e segurança

O validador da mídia é somente leitura. Ele verifica a estrutura básica do instalador e reprova um `autounattend.xml` que contenha seleção de imagem/disco, partições, usuários, senhas, chave de produto, comandos ou arquivos embutidos.

O `pc-setup` mostra o plano antes de alterar o Windows. A aplicação só começa depois de criar e consultar um ponto de restauração obrigatório. O BitLocker permanece sem configuração automática e o debloat fica separado e desabilitado.

## Auditoria e teste

- [`docs/AUDITORIA-INSTALACAO-ATUAL.md`](docs/AUDITORIA-INSTALACAO-ATUAL.md): o que a automação antiga realmente executou e onde falhou;
- [`docs/TESTE-EM-VM.md`](docs/TESTE-EM-VM.md): quando uma VM ajuda e por que o Windows Sandbox não valida o fluxo completo.

## Referências oficiais

- [Visão geral da automação do Windows Setup](https://learn.microsoft.com/windows-hardware/manufacture/desktop/windows-setup-automation-overview?view=windows-11)
- [Automatizar o Windows Setup](https://learn.microsoft.com/windows-hardware/manufacture/desktop/automate-windows-setup?view=windows-11)
- [Como funcionam as fases de configuração](https://learn.microsoft.com/windows-hardware/manufacture/desktop/how-configuration-passes-work?view=windows-11)
