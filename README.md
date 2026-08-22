# pc-setup

Setup reproduzivel do meu PC pessoal com **Windows 11 Pro 25H2**.

A ideia nao e preservar uma instalacao para sempre. A ideia e conseguir apagar o PC e reconstruir um ambiente conhecido, documentado e verificavel.

> Em agosto de 2026, o Windows 11 26H1 existe, mas a Microsoft o destina a novos dispositivos de 2026 e nao o oferece como feature update para PCs existentes em 24H2/25H2. Para esta maquina, o target correto e Windows 11 Pro 25H2.

## Arquitetura

```text
Windows 11 Pro 25H2
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

O Fabio Akita citou o projeto de debloat do LeDragoX no Akitando #114. Aquele projeto foi arquivado em 2025 e nao e mais a base usada aqui.

Para Windows 11 Pro 25H2, este setup usa o **Raphire/Win11Debloat**, atualmente mantido, fixado na release:

```text
2026.07.11
```

Nao executamos uma URL remota flutuante. O wrapper baixa a release fixa e roda automaticamente:

```powershell
Win11Debloat.ps1 -RunDefaults -Silent -CreateRestorePoint
```

Execute explicitamente depois de Windows Update e drivers:

```powershell
.\scripts\50-debloat-akita.ps1
```

O preset nao usa `-RemoveGamingApps`, porque este PC tambem sera usado para jogos.

Veja `docs/DEBLOAT.md` antes de executar.

## Principios

- usuario diario nao e administrador;
- configuracao importante vira script ou documentacao;
- script deve poder rodar novamente sem destruir a maquina;
- Git nao e backup, mas e a primeira camada de recuperacao para codigo/config;
- backup precisa existir fora do PC;
- restore precisa ser testado;
- segredos nunca entram neste repositorio;
- `God` e break-glass, nao fluxo normal;
- software desconhecido vai para Sandbox/VM antes do host;
- automacao deve ser versionada e previsivel, nao depender do estado atual de uma URL externa.

## Ordem recomendada

1. Backup e recovery keys.
2. Verificar a causa da desconexao do SSD D.
3. Instalar Windows 11 Pro **25H2** no NVMe.
4. Windows Update + drivers.
5. Clonar este repositorio.
6. Rodar `bootstrap.ps1`.
7. Reiniciar quando solicitado.
8. Configurar usuarios e testar Admin.
9. Rodar `scripts/50-debloat-akita.ps1`.
10. Reiniciar e validar Store/jogos/dispositivos.
11. Configurar WSL/Hyper-V/VM Publico.
12. Rodar `verify.ps1`.
13. Criar uma imagem/backup do estado limpo.

## Referencias

- Akita Akitando #114: https://akitaonrails.com/2022/02/15/akitando-114-o-melhor-setup-dev-com-arch-e-wsl2/
- Win11Debloat: https://github.com/Raphire/Win11Debloat
- Windows 11 release health: https://learn.microsoft.com/windows/release-health/windows11-release-information
- Microsoft Hyper-V: https://learn.microsoft.com/windows-server/virtualization/hyper-v/
- Microsoft WSL: https://learn.microsoft.com/windows/wsl/
- Windows Sandbox: https://learn.microsoft.com/windows/security/application-security/application-isolation/windows-sandbox/
- OpenAI Codex: https://developers.openai.com/codex/
