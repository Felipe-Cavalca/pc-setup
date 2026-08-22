# Teste em máquina virtual

Não é necessário criar uma VM para executar o `pc-setup` no computador real.

Uma VM Hyper-V é útil apenas para ensaiar a instalação completa sem tocar nos discos físicos. Use um disco virtual descartável e um checkpoint antes do teste.

## O que testar

1. iniciar a VM pela mídia oficial;
2. confirmar que as telas esperadas aparecem;
3. instalar o Windows no disco virtual;
4. concluir o OOBE;
5. copiar o repositório para a VM;
6. revisar uma configuração específica para a VM;
7. executar primeiro o plano;
8. aplicar somente se quiser validar também recursos, programas e reinício.

Para testar Hyper-V ou WSL dentro da VM, o host precisa expor extensões de virtualização aninhada. Isso é uma preparação opcional do laboratório, não um requisito do computador real.

## Por que não usar Windows Sandbox

O Windows Sandbox serve para testar aplicativos isolados, mas não simula o boot pelo instalador nem a instalação do Windows em disco. A Microsoft também informa que recursos opcionais ativados por “Ativar ou desativar recursos do Windows” não são suportados dentro do Sandbox.

Assim, o Sandbox pode verificar apenas scripts simples e não destrutivos. Ele não é uma validação válida do fluxo completo de armazenamento, Hyper-V, WSL, reinício e retomada.

Referências:

- [Perguntas frequentes sobre Windows Sandbox](https://learn.microsoft.com/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-faq)
- [Virtualização aninhada no Hyper-V](https://learn.microsoft.com/virtualization/hyper-v-on-windows/user-guide/nested-virtualization)
