# Teste em máquina virtual

A VM não é requisito para executar o `pc-setup` em hardware físico.

Uma VM Hyper-V é útil para ensaiar a instalação completa sem tocar nos discos físicos. O ambiente de teste deve usar um disco virtual descartável e um checkpoint anterior à execução.

## O que testar

1. iniciar a VM pela mídia oficial;
2. confirmar que as telas esperadas aparecem;
3. instalar o Windows no disco virtual;
4. concluir o OOBE;
5. copiar o repositório para a VM;
6. revisar uma configuração específica para a VM;
7. executar primeiro o plano;
8. aplicar somente quando o objetivo incluir recursos, programas e retomada após reinício.

Para testar Hyper-V ou WSL dentro da VM, o host precisa expor extensões de virtualização aninhada. Essa preparação pertence ao laboratório e não é requisito do uso em hardware físico.

## Por que não usar Windows Sandbox

O Windows Sandbox serve para testar aplicativos isolados, mas não simula o boot pelo instalador nem a instalação do Windows em disco. A Microsoft também informa que recursos opcionais ativados por “Ativar ou desativar recursos do Windows” não são suportados dentro do Sandbox.

Assim, o Sandbox pode verificar apenas scripts simples e não destrutivos. Ele não é uma validação válida do fluxo completo de armazenamento, Hyper-V, WSL, reinício e retomada.

Referências:

- [Perguntas frequentes sobre Windows Sandbox](https://learn.microsoft.com/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-faq)
- [Virtualização aninhada no Hyper-V](https://learn.microsoft.com/virtualization/hyper-v-on-windows/user-guide/nested-virtualization)
