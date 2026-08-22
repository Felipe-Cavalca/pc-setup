# Ambientes WSL

O bootstrap principal habilita os recursos do Windows, atualiza o WSL e define a versão 2 como padrão. A distribuição Linux é configurada depois, dentro da sessão de cada conta Windows, porque o registro e o filesystem de uma distribuição WSL pertencem ao usuário Windows que a instalou.

O perfil versionado prevê dois ambientes independentes:

- `DailyUser`: conta Windows `Felipe`, distribuição `Ubuntu-24.04` e usuário Linux `felipe`;
- `Codex`: conta Windows `Codex`, distribuição `Ubuntu-24.04` e usuário Linux `codex`.

As duas contas podem usar o mesmo nome de distribuição sem compartilhar rootfs, pacotes ou arquivos. `Codex` continua sendo usuário padrão no Windows. A conta administrativa de emergência não recebe ambiente WSL por padrão.

## Aplicar por usuário

Depois que o bootstrap principal terminar e o Windows tiver sido reiniciado, entre na conta correspondente e abra o Windows PowerShell 5.1 sem elevação na raiz do projeto. O script chama somente as operações Linux necessárias como `root` dentro daquela distribuição.

Antes disso, deixe o checkout em um caminho acessível às duas contas, preferencialmente no diretório de desenvolvimento criado pelo setup, como `D:\Dev\pc-setup`. Uma cópia mantida dentro da área de trabalho de uma conta pode não estar acessível à outra.

Para o usuário diário:

```powershell
.\wsl\bootstrap.ps1 -Environment DailyUser -Plan
.\wsl\bootstrap.ps1 -Environment DailyUser -Apply
.\wsl\verify.ps1 -Environment DailyUser
```

Para o Codex:

```powershell
.\wsl\bootstrap.ps1 -Environment Codex -Plan
.\wsl\bootstrap.ps1 -Environment Codex -Apply
.\wsl\verify.ps1 -Environment Codex
```

O bootstrap é idempotente: reutiliza a distribuição registrada, garante o usuário Linux, instala os pacotes APT declarados, cria a raiz de projetos, define o usuário padrão da distribuição e atualiza o manifesto de versões. Nenhuma senha ou credencial é gravada.

Os perfis ficam em [`profiles`](profiles). O estado Linux fica em `/var/lib/pc-setup/<ambiente>/installed.tsv`; os relatórios PowerShell ficam em `%LOCALAPPDATA%\pc-setup\reports` da conta Windows correspondente.

## Onde guardar projetos

Use o filesystem Linux, como `/home/felipe/Dev` ou `/home/codex/Dev`, quando o trabalho for executado principalmente por ferramentas Linux. É a melhor opção para Git, `node_modules`, `vendor`, builds, containers e árvores com muitos arquivos pequenos.

Use um caminho montado, como `/mnt/d/Dev`, quando os mesmos arquivos precisarem ser acessados principalmente por ferramentas Windows ou compartilhados diretamente com elas. Se a raiz de desenvolvimento do Windows estiver em outro volume, adapte a letra e o caminho, por exemplo `/mnt/c/Dados/Dev`.

Evite manter um único checkout com ferramentas Windows e Linux alternadas. Além de diferenças de permissões e finais de linha, operações feitas pelo Linux em `/mnt/c` ou `/mnt/d` normalmente são mais lentas do que no filesystem da distribuição.

Arquivos do filesystem Linux continuam acessíveis no Explorer por `\\wsl$\Ubuntu-24.04\home\<usuario>`, mas builds e gerenciadores de pacotes devem ser executados dentro do WSL.

## Configuração

`config/machine.psd1` liga uma conta Windows a uma distribuição e a um perfil declarativo:

```powershell
WSL = @{
    DefaultVersion = 2
    Environments = @{
        Codex = @{
            Enabled      = $true
            AccountKey   = 'Codex'
            Distribution = 'Ubuntu-24.04'
            Profile      = 'wsl\profiles\codex.psd1'
        }
    }
}
```

Para outra máquina, altere apenas configurações não secretas: conta, distribuição, usuário Linux, raiz de projetos e lista de pacotes.

## Referências

- [Trabalhar entre os filesystems Windows e Linux](https://learn.microsoft.com/windows/wsl/filesystems)
- [Comandos básicos do WSL](https://learn.microsoft.com/windows/wsl/basic-commands)
