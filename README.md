# pc-setup

Setup reproduzível e configurável para Windows 11 Pro. O perfil padrão representa a máquina do Felipe; outro computador usa o mesmo código e troca apenas o arquivo `.psd1`.

O projeto trabalha em duas etapas: primeiro mostra e registra tudo o que pretende fazer; depois aplica exatamente a configuração revisada. Senhas, tokens e chaves nunca ficam no repositório.

## Resultado do perfil padrão

- valida Windows 11 Pro 25H2 e build mínima 26200;
- usa o volume do Windows detectado em tempo de execução;
- usa automaticamente um único segundo disco fixo com volume NTFS saudável, quando houver;
- sem segundo disco, cria `Dados` no volume do Windows;
- cria a estrutura de dados configurada;
- cria `Admin` como administrador e `Codex` como usuário padrão;
- preserva `Felipe` como administrador até o login de `Admin` ser testado;
- aplica ACLs isolando dados pessoais e dados do agente, com backup e rollback;
- habilita Hyper-V, Windows Sandbox, Virtual Machine Platform e WSL;
- instala Chrome, Bitwarden, WinRAR, Google Drive, ferramentas de desenvolvimento e launchers de jogos pelo Winget;
- atualiza e configura WSL 2, sem impor uma distribuição;
- gera relatórios JSON de plano, aplicação e validação;
- apenas informa o estado do BitLocker, sem configurá-lo.

As contas `God` e `Publico`, a VM pública, o plano de fundo e o debloat ficam desabilitados por padrão.

## Antes de executar

1. Termine o Windows Update e instale os drivers.
2. Habilite manualmente a Proteção do Sistema no volume do Windows.
3. Confirme que o Windows está ativado.
4. Abra o **Windows PowerShell 5.1 como Administrador**.
5. Revise [`config/machine.psd1`](config/machine.psd1).

O setup não habilita a Proteção do Sistema sozinho. Se não conseguir criar e consultar o ponto de restauração obrigatório, nenhuma etapa de aplicação começa.

## Executar

Na pasta do projeto:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\bootstrap.ps1 -Config .\config\machine.psd1 -Plan
```

Leia o plano mostrado e o caminho do relatório. Se a escolha do disco, usuários, recursos e programas estiver correta:

```powershell
.\bootstrap.ps1 -Config .\config\machine.psd1 -Apply
```

O recibo inclui a impressão SHA-256 dos scripts, da configuração e dos perfis de pacotes. Qualquer mudança relevante exige gerar o plano novamente.

As senhas são solicitadas somente para contas habilitadas que ainda não existam. Elas permanecem apenas na memória do processo.

Se recursos do Windows exigirem reinício, o script para e mostra a instrução. Reinicie e execute o mesmo comando `-Apply`. A retomada valida e reutiliza o ponto pertencente àquela aplicação; um ponto antigo de outra execução nunca é aceito.

Ao terminar:

```powershell
.\verify.ps1 -Config .\config\machine.psd1
```

O verificador classifica cada item como `PASS`, `WARN`, `FAIL` ou `INFO`. Avisos exigem revisão; falhas fazem o comando retornar código 1.

## O que aparece durante a execução

No plano, você verá:

- perfil e arquivo de configuração usados;
- volume atual do Windows e raiz escolhida para dados;
- recursos que serão habilitados;
- diretórios e contas que serão criados;
- permissões que serão aplicadas;
- IDs dos programas e disponibilidade de fallback offline;
- configuração prevista para WSL e personalização;
- estado do debloat separado.

Na aplicação, cada etapa mostra `OK`, `CRIADO`, `APLICAR`, `WINGET`, `OFFLINE`, `RECOVERY` ou uma mensagem de erro. Códigos de erro de ferramentas externas são tratados como falha.

## Armazenamento

O perfil padrão usa:

```powershell
SecondaryDiskPolicy    = 'UseIfAvailable'
OnMultipleCandidates  = 'Stop'
SingleDiskFallbackRoot = '{SystemRoot}\Dados'
AllowRemovableVolumes  = $false
```

Isso significa:

- um único volume NTFS saudável em um segundo disco fixo: usa esse volume;
- nenhum segundo disco: usa `Dados` no volume do Windows;
- segundo disco sem volume NTFS utilizável: interrompe e pede preparação no Gerenciamento de Disco;
- vários volumes candidatos: interrompe para não escolher por adivinhação;
- unidade removível: não é escolhida automaticamente.

Modelo, tamanho, rótulo, barramento e letra não são fixados. A raiz escolhida no plano precisa ser a mesma na aplicação.

Para forçar uma máquina com somente um disco, use como base [`config/examples/machine-one-disk.psd1`](config/examples/machine-one-disk.psd1).

## Diretórios e permissões

Os nomes abaixo são relativos à raiz de dados escolhida:

```text
Apps
Games
Dev
Data\<usuario principal>
Shared
Downloads
VMs
Containers
Agent\Codex
```

As ACLs protegidas são:

- `Dev`: usuário principal e `Codex` com modificação;
- dados pessoais: somente usuário principal, SYSTEM e Administradores;
- dados do agente: somente `Codex`, SYSTEM e Administradores.

Antes da alteração, o script exporta as ACLs para `%ProgramData%\pc-setup\acl-backups`. Se uma aplicação falhar, ele tenta restaurar todos os backups daquela execução.

Perfis do Windows, `AppData`, `ProgramData` e componentes do sistema não são movidos.

A criação dessas pastas não redireciona automaticamente bibliotecas da Steam, dados do Docker ou o destino escolhido pelos instaladores. Esses ajustes continuam específicos de cada programa.

## Programas

Os perfis ficam em [`config/packages`](config/packages):

- `base`: Chrome, Bitwarden, WinRAR e Google Drive;
- `development`: Git, PowerShell, Windows Terminal, VS Code e Docker Desktop;
- `gaming`: Steam e Epic Games Launcher.

O Winget consulta a fonte oficial configurada no Windows e tenta instalar a versão atual. Em caso de falha, um instalador offline só é aceito quando consta em [`config/offline-installers.psd1`](config/offline-installers.psd1), existe dentro da pasta permitida e tem SHA-256 idêntico ao manifesto. O manifesto vem vazio; adicione apenas arquivos revisados.

## Configuração para outra pessoa

Copie `config/machine.psd1` e altere, principalmente:

- `Machine.PrimaryUser`;
- nomes, funções e `Enabled` das contas;
- política do segundo disco;
- recursos opcionais;
- perfis de programas;
- distribuição WSL, se desejar uma instalação automática.

Exemplo:

```powershell
.\bootstrap.ps1 -Config .\config\minha-maquina.psd1 -Plan
.\bootstrap.ps1 -Config .\config\minha-maquina.psd1 -Apply
```

Veja todas as decisões em [`config/README.md`](config/README.md).

## Recuperação e relatórios

O Windows limita `Checkpoint-Computer` a um ponto por período de 24 horas. Por isso, uma aplicação cria um ponto único. Scripts internos o validam e reutilizam; a continuação depois do reinício usa o mesmo identificador salvo em `%ProgramData%\pc-setup\apply-state.json`.

Executar um script de alteração diretamente com `-Apply` exige um novo ponto. `-Plan`, `verify.ps1`, testes e o lançador da VM não alteram a configuração do Windows e não criam ponto.

Relatórios e estado ficam em `%ProgramData%\pc-setup`. Um ponto de restauração protege configurações e arquivos de sistema, mas não substitui backup dos arquivos pessoais.

## Etapas opcionais

### Plano de fundo

Coloque uma imagem dentro do projeto, configure `Personalization.WallpaperPath` e mude `Enabled` para `$true`. A alteração é aplicada ao usuário que executa o bootstrap.

### Debloat

O debloat não faz parte do bootstrap de aplicação. Ele permanece desabilitado e exige versão fixa, SHA-256 válido, leitura da documentação e confirmação explícita. Veja [`docs/DEBLOAT.md`](docs/DEBLOAT.md).

### VM pública e conta God

Essas contas não são criadas pelo perfil padrão. A criação da VM ainda é uma decisão manual; o projeto inclui apenas um lançador configurável para uma VM que já exista.

## Testes do projeto

Os testes não alteram o Windows nem criam ponto real:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run.ps1
```

## Referências

- [Akitando #114](https://akitaonrails.com/2022/02/15/akitando-114-o-melhor-setup-dev-com-arch-e-wsl2/)
- [System Protection](https://support.microsoft.com/en-us/windows/experience/backup-recovery/system-protection)
- [Checkpoint-Computer](https://learn.microsoft.com/pt-br/powershell/module/microsoft.powershell.management/checkpoint-computer?view=powershell-5.1)
- [Windows 11 release information](https://learn.microsoft.com/windows/release-health/windows11-release-information)
- [Win11Debloat](https://github.com/Raphire/Win11Debloat)
