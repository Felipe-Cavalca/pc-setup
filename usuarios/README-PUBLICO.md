# Publico

Usuario Windows **Standard** usado apenas como launcher de uma VM Hyper-V chamada `Publico`.

```text
Login Publico
-> VMConnect
-> VM Publico
-> navegador/e-mail/faturas
```

Nao adicionar a `Administrators` nem `Hyper-V Administrators`.

No host, nao deve existir dado pessoal nem acesso a `D:\Dev` ou `D:\Data\Felipe`.

A VM e persistente e pode manter navegador/configuracoes proprias. Se o guest for Windows, ele precisa de licenca valida propria.

O script `scripts/publico-abrir-vm.ps1` abre a VM. Configure-o para rodar no logon do usuario Publico depois que a VM existir.

No Windows 11 Pro isso nao substitui o shell como o Shell Launcher Enterprise; e um launcher restrito + VM em tela cheia.
