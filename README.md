# pc-setup

Setup reproduzivel do meu PC pessoal com **Windows 11 Pro 25H2**.

O objetivo deste repositorio e deixar a instalacao e configuracao da maquina documentadas e automatizadas.

> Em agosto de 2026, o Windows 11 26H1 existe, mas a Microsoft o destina a novos dispositivos de 2026 e nao o oferece como feature update para PCs existentes em 24H2/25H2. Para esta maquina, o target correto e Windows 11 Pro 25H2.

## Arquitetura

```text
Windows 11 Pro 25H2
├── Felipe   -> usuario padrao, uso diario
├── Admin    -> administrador humano / manutencao
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

Para Windows 11 Pro 25H2, este setup usa o **Raphire/Win11Debloat**, fixado na release:

```text
2026.07.11
```

O wrapper baixa a release fixa e executa:

```powershell
Win11Debloat.ps1 -RunDefaults -Silent -CreateRestorePoint
```

Execute depois de Windows Update e drivers:

```powershell
.\scripts\50-debloat-akita.ps1
```

O preset nao usa `-RemoveGamingApps`, porque este PC tambem sera usado para jogos.

Veja `docs/DEBLOAT.md` antes de executar.

## Regras do setup

- usuario diario nao e administrador;
- configuracao importante vira script ou documentacao;
- scripts devem poder ser executados novamente;
- segredos nunca entram neste repositorio;
- `God` e reservado para configuracao administrativa;
- software desconhecido vai para Sandbox/VM antes do host;
- automacao externa fica fixada em uma versao conhecida.

## Ordem recomendada

1. Verificar a causa da desconexao do SSD D.
2. Instalar Windows 11 Pro **25H2** no NVMe.
3. Executar Windows Update e instalar drivers.
4. Clonar este repositorio.
5. Rodar `bootstrap.ps1`.
6. Reiniciar quando solicitado.
7. Testar a conta Admin.
8. Rodar `scripts/50-debloat-akita.ps1`.
9. Reiniciar e validar Store, jogos e dispositivos.
10. Configurar WSL, Hyper-V e VM Publico.
11. Rodar `verify.ps1`.

## Referencias

- Akita Akitando #114: https://akitaonrails.com/2022/02/15/akitando-114-o-melhor-setup-dev-com-arch-e-wsl2/
- Win11Debloat: https://github.com/Raphire/Win11Debloat
- Windows 11 release health: https://learn.microsoft.com/windows/release-health/windows11-release-information
- Microsoft Hyper-V: https://learn.microsoft.com/windows-server/virtualization/hyper-v/
- Microsoft WSL: https://learn.microsoft.com/windows/wsl/
- Windows Sandbox: https://learn.microsoft.com/windows/security/application-security/application-isolation/windows-sandbox/
- OpenAI Codex: https://developers.openai.com/codex/
