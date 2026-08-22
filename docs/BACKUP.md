# Backup e recuperacao

## Camadas

```text
Git                 -> erro de codigo/config
Versionamento       -> arquivo alterado/apagado
Backup externo      -> falha de disco/ransomware
Off-site/cloud      -> roubo/desastre fisico
```

Git nao substitui backup.

## Regras

- pelo menos uma copia importante fora do PC;
- preferir backup versionado;
- disco externo de backup nao precisa ficar conectado permanentemente;
- segredos e recovery keys precisam de copia segura fora da maquina;
- testar restore periodicamente.

## Teste de restore

Escolha periodicamente um projeto ou documento:

1. restaure para outra pasta;
2. compare os arquivos;
3. abra/compile/teste quando aplicavel;
4. registre qualquer falha do processo neste repositorio.

Backup que nunca foi restaurado ainda nao foi validado.
