# pc-setup

Setup reproduzivel do meu PC pessoal com **Windows 11 Pro**.

A ideia nao e preservar uma instalacao para sempre. A ideia e conseguir apagar o PC e reconstruir um ambiente conhecido, documentado e verificavel.

## Arquitetura

```text
Windows 11 Pro
├── Felipe   -> usuario padrao, uso diario
├── Admin    -> administrador humano / recuperacao
├── Codex    -> usuario padrao exclusivo do agente
├── God      -> administrador exclusivo do agente
├── Publico  -> usuario host que abre a VM Publico
├── WSL2     -> Linux/dev
├── Hyper-V  -> VMs persistentes
└── Sandbox  -> execucao descartavel
```

## Discos

```text
C: NVMe 256 GB
├── Windows
├── Users
├── drivers
└── componentes essenciais

D: SSD 1 TB
├── Apps
├── Games
├── Dev
├── Data\Felipe
├── Shared
├── Downloads
├── VMs
├── Containers
└── Agent\Codex
```

**Regra:** o `C:` precisa continuar inicializavel e administravel se o `D:` desconectar.

Nao mover `C:\Users`, `AppData`, `ProgramData` ou componentes do Windows para o D.

## Instalacao

Abra PowerShell como administrador:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\bootstrap.ps1
```

O bootstrap chama scripts pequenos e idempotentes. Leia-os antes de executar.

Depois:

```powershell
.\verify.ps1
```

## Debloat

O Fabio Akita citou o **Win10 Smart Debloat / Win-Debloat-Tools, do LeDragoX**, no Akitando #114.

Este projeto foi arquivado em **2025-10-03**. Por isso este repo nao executa uma URL flutuante: `scripts/50-debloat-akita.ps1` baixa o commit final fixo:

```text
4766a980ce25a5d130f7c8e801550afab876cd34
```

O projeto arquivado declara suporte ate Windows 11 **24H2 ou anterior**. Em versao mais nova, o script aborta por padrao.

Execute explicitamente:

```powershell
.\scripts\50-debloat-akita.ps1
```

Veja `docs/DEBLOAT.md`.

## Principios

- usuario diario nao e administrador;
- configuracao importante vira script ou documentacao;
- script deve poder rodar novamente sem destruir a maquina;
- Git nao e backup, mas e a primeira camada de recuperacao para codigo/config;
- backup precisa existir fora do PC;
- restore precisa ser testado;
- segredos nunca entram neste repositorio;
- `God` e break-glass, nao fluxo normal;
- software desconhecido vai para Sandbox/VM antes do host.

## Ordem recomendada

1. Backup e recovery keys.
2. Verificar a causa da desconexao do SSD D.
3. Instalar Windows 11 Pro no NVMe.
4. Windows Update + drivers.
5. Clonar este repositorio.
6. Rodar `bootstrap.ps1`.
7. Reiniciar quando solicitado.
8. Configurar usuarios e testar Admin.
9. Aplicar debloat somente depois de conferir compatibilidade.
10. Configurar WSL/Hyper-V/VM Publico.
11. Rodar `verify.ps1`.
12. Criar uma imagem/backup do estado limpo.

## Referencias

- Akita Akitando #114: https://akitaonrails.com/2022/02/15/akitando-114-o-melhor-setup-dev-com-arch-e-wsl2/
- LeDragoX Win-Debloat-Tools: https://github.com/LeDragoX/Win-Debloat-Tools
- Microsoft Hyper-V: https://learn.microsoft.com/windows-server/virtualization/hyper-v/
- Microsoft WSL: https://learn.microsoft.com/windows/wsl/
- Windows Sandbox: https://learn.microsoft.com/windows/security/application-security/application-isolation/windows-sandbox/
- OpenAI Codex: https://developers.openai.com/codex/
