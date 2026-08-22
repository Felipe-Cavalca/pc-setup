# Checklist de instalacao

## Antes

- [ ] Confirmar ativacao/licenca do Windows 11 Pro.
- [ ] Verificar SMART/saude dos dois discos.
- [ ] Investigar a desconexao intermitente do SSD D.
- [ ] Baixar drivers essenciais caso a rede nao funcione apos formatar.

## BIOS/UEFI

- [ ] UEFI.
- [ ] Secure Boot.
- [ ] TPM.
- [ ] VT-x/AMD-V.

## Windows

- [ ] Instalar **Windows 11 Pro 25H2** no C (NVMe).
- [ ] Confirmar build `26200` ou posterior.
- [ ] Windows Update completo.
- [ ] Drivers instalados.
- [ ] Windows ativado.
- [ ] D em NTFS.

> Nao forcar Windows 11 26H1 nesta maquina existente: essa release e destinada a novos dispositivos de 2026 e nao e oferecida como feature update para PCs 24H2/25H2 existentes.

## Setup

- [ ] Clonar `pc-setup`.
- [ ] Ler `bootstrap.ps1`.
- [ ] Rodar bootstrap como administrador.
- [ ] Reiniciar se necessario.
- [ ] Testar login do Admin antes de remover privilegio administrativo do Felipe.
- [ ] Ler `docs/DEBLOAT.md`.
- [ ] Rodar `scripts/50-debloat-akita.ps1`.
- [ ] Reiniciar depois do debloat.
- [ ] Testar Microsoft Store, Device Manager e Windows Update.
- [ ] Testar Xbox/Gaming.
- [ ] Configurar Codex.
- [ ] Configurar God.
- [ ] Configurar WSL2.
- [ ] Criar VM Publico.
- [ ] Configurar launcher Publico.
- [ ] Rodar `verify.ps1`.

## Teste da arquitetura

- [ ] Desligar corretamente.
- [ ] Testar boot sem o SSD D conectado.
- [ ] Confirmar que Windows, Admin e ferramentas basicas continuam utilizaveis.
- [ ] Reconectar D e validar Apps/Dev/Games/VMs.

## Final

- [ ] Rodar `verify.ps1` sem falhas.
- [ ] Commitar qualquer ajuste manual que precise fazer parte do setup no futuro.
