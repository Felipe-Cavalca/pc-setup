# Arquivos da mídia

`Validar-Midia.cmd` e `Validar-Midia.ps1` devem ser copiados para a raiz da mídia. O `.cmd` executa uma validação somente leitura antes da instalação.

`autounattend.pt-BR.opcional.xml` é opcional. Quando necessário, uma cópia deve ser colocada na raiz com o nome `autounattend.xml`. O modelo define apenas idioma, região e teclado em português do Brasil.

Instaladores e comandos não pertencem ao XML nem à mídia. Toda configuração pós-instalação é executada pelo `pc-setup` depois do primeiro login.
