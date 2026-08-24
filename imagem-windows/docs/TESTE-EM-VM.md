# Teste em máquina virtual

A VM não é requisito para executar o `pc-setup` em hardware físico. Ela é o ambiente recomendado para ensaiar o fluxo completo antes de aplicá-lo à máquina principal.

## VM recomendada

Crie no Hyper-V uma VM descartável com:

- geração 2;
- Inicialização Segura e TPM virtual habilitados;
- 4 processadores virtuais;
- 8 GB de memória ou mais;
- VHDX dinâmico de 120 GB ou mais;
- Windows 11 Pro da mesma arquitetura prevista no perfil.

Os mínimos oficiais do Windows 11 são 2 processadores virtuais, 4 GB de memória e 64 GB de armazenamento. Os valores maiores acima evitam que instalação, Winget, WSL e testes concorram por poucos recursos.

Para validar WSL 2 ou Hyper-V dentro da VM, desligue a VM e execute no host, em PowerShell como Administrador:

```powershell
Set-VMProcessor -VMName 'pc-setup-test' -ExposeVirtualizationExtensions $true
```

Troque `pc-setup-test` pelo nome real. Essa virtualização aninhada pertence somente ao laboratório.

O plano executa um preflight antes de alterar recursos opcionais. Se as extensões não estiverem expostas, ele interrompe com uma orientação para o host e não inicia a habilitação de Hyper-V, Sandbox ou WSL 2.

Para testar a pergunta sobre um segundo disco, conecte um segundo VHDX à VM e, dentro dela, inicialize-o, crie um volume NTFS e atribua uma letra. Não use dados reais nesse disco. Repita também o teste apenas com o disco do sistema.

## Roteiro completo

1. Inicie a VM pela ISO oficial e instale o Windows 11 Pro.
2. No OOBE, crie a conta diária com o nome definido em `Accounts.DailyUser.Name`; no perfil padrão, `Felipe`.
3. Conclua o Windows Update, os drivers e a ativação necessária ao laboratório.
4. Habilite manualmente a Proteção do Sistema no volume do Windows.
5. Crie um checkpoint da VM.
6. Copie para a VM exatamente a revisão do repositório que será testada.
7. Revise `config\machine.psd1`, principalmente contas, disco, pacotes e recursos.
8. Execute `tests\run-all.ps1` no Windows PowerShell 5.1.
9. Dê duplo clique em `INSTALAR.cmd`, confira o plano e confirme apenas se estiver correto.
10. Quando solicitado, reinicie e execute `INSTALAR.cmd` novamente.
11. Confirme que Windows, WSL, usuário Linux diário e `agent` foram validados.
12. Execute `AGENTE.cmd`, escolha um projeto descartável e confirme que o agente enxerga somente o workspace liberado.
13. Altere uma opção não destrutiva da configuração e execute `ATUALIZAR.cmd` para validar a reconciliação.

Se pacotes, personalização ou WSL falharem depois que o Windows terminar, corrija a causa e execute o mesmo arquivo novamente. A retomada deve informar que o Windows já foi aplicado e executar apenas as fases da conta diária. Se a configuração, os scripts ou o prazo do comprovante protegido tiverem mudado, o Windows será planejado novamente.

## O que conferir

- o plano identifica corretamente zero, um ou vários discos de dados;
- nenhuma aplicação começa sem ponto de restauração válido;
- a retomada após reinício preserva a escolha feita no plano;
- `Felipe` permanece Administrador enquanto a conta `Admin` ainda não foi validada, conforme a configuração padrão;
- todas as contas habilitadas aparecem como membros do grupo local `Usuários` e permitem logon; se a conta diária ainda não tiver bloco próprio, use `Outro usuário` com `.\Felipe` no primeiro acesso;
- `Publico` é usuário padrão e recebe Edge e Chrome;
- a distribuição `Ubuntu-24.04` usa o usuário diário como padrão;
- o usuário Linux `agent` não tem `sudo`, mantém autenticação própria e usa o `ai-jail`;
- os relatórios em `%ProgramData%\pc-setup` e `%LOCALAPPDATA%\pc-setup\reports` terminam com sucesso;
- Chrome aparece para `Publico`, enquanto pacotes configurados como `user` pertencem somente à conta diária;
- uma segunda execução completa não duplica contas, diretórios ou configuração.

O debloat tem confirmação própria. Teste-o somente depois de criar outro checkpoint, pois a restauração do checkpoint é a forma mais rápida de repetir o laboratório.

## Por que não usar Windows Sandbox

O Windows Sandbox serve para testes isolados de aplicativos, mas não reproduz a instalação do Windows em disco, o boot, os recursos opcionais, a virtualização aninhada, os reinícios e a retomada do `pc-setup`. Ele pode ajudar em verificações simples e não destrutivas, mas não valida este fluxo completo.

Referências oficiais:

- [Requisitos do Windows 11 para máquinas virtuais](https://learn.microsoft.com/windows/whats-new/windows-11-requirements)
- [Perguntas frequentes do WSL](https://learn.microsoft.com/windows/wsl/faq)
- [Virtualização aninhada no Hyper-V](https://learn.microsoft.com/windows-server/virtualization/hyper-v/enable-nested-virtualization)
- [Perguntas frequentes sobre Windows Sandbox](https://learn.microsoft.com/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-faq)
