# Checklist de formatacao

## Antes

- [ ] Backup de projetos e documentos.
- [ ] Export/backup das chaves SSH privadas em local seguro.
- [ ] Guardar recovery keys do BitLocker fora do PC.
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

- [ ] Windows 11 Pro instalado no C (NVMe).
- [ ] Windows Update completo.
- [ ] Drivers instalados.
- [ ] Windows ativado.
- [ ] D em NTFS.

## Setup

- [ ] Clonar `pc-setup`.
- [ ] Ler `bootstrap.ps1`.
- [ ] Rodar bootstrap como administrador.
- [ ] Reiniciar se necessario.
- [ ] Testar login do Admin antes de remover privilegio administrativo do Felipe.
- [ ] Aplicar debloat compativel.
- [ ] Configurar Codex.
- [ ] Configurar God.
- [ ] Configurar WSL2.
- [ ] Criar VM Publico.
- [ ] Configurar launcher Publico.
- [ ] Rodar `verify.ps1`.

## Teste de falha

- [ ] Desligar corretamente.
- [ ] Testar boot sem o SSD D conectado.
- [ ] Confirmar que Windows, Admin e ferramentas basicas continuam utilizaveis.
- [ ] Reconectar D e validar dados.

## Final

- [ ] Backup do estado limpo.
- [ ] Teste real de restore de pelo menos um arquivo/projeto.
- [ ] Commitar qualquer ajuste manual que precise ser repetido no futuro.
