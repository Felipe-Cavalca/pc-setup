# Usuário público

Conta Windows **Standard** opcional, destinada apenas a abrir uma VM Hyper-V dedicada.

```text
Login no usuário público
-> VMConnect
-> VM dedicada
-> aplicativos e dados do convidado
```

A conta não deve pertencer a `Administrators` nem `Hyper-V Administrators`. O host não deve expor dados pessoais nem os diretórios `Development` e `PersonalData` configurados.

A VM pode ser persistente e manter aplicativos e configurações próprias. Um sistema convidado Windows exige licença válida independente.

O script `scripts/publico-abrir-vm.ps1` abre a VM indicada na configuração. O acionamento no logon só deve ser configurado depois que a VM existir e estiver validada.

No Windows 11 Pro, essa abordagem é um launcher restrito em tela cheia; não substitui o Shell Launcher disponível em edições Enterprise.
