# Debloat

## O que o Akita recomendou

No **Akitando #114 (2022)**, Fabio Akita recomenda rodar debloat apos uma instalacao limpa do Windows e aponta o **Win10 Smart Debloat**, de LeDragoX.

O projeto evoluiu para `LeDragoX/Win-Debloat-Tools`.

## Situacao atual

O repositorio foi arquivado pelo autor em **3 de outubro de 2025**. O commit final e:

```text
4766a980ce25a5d130f7c8e801550afab876cd34
```

A documentacao final declara suporte para Windows 11 **24H2 ou anterior**.

Por isso:

- nao usamos `irm URL | iex` em uma URL que pode mudar;
- baixamos um commit fixo;
- recusamos executar em versao posterior a 24H2, a menos que `-ForceUnsupported` seja passado conscientemente;
- o debloat nao roda escondido no `bootstrap.ps1`.

## Executar

```powershell
.\scripts\50-debloat-akita.ps1
```

Forcar uma versao nao declarada como suportada:

```powershell
.\scripts\50-debloat-akita.ps1 -ForceUnsupported
```

**Nao recomendado.** Se estiver em Windows posterior a 24H2, prefira estudar uma ferramenta mantida para a sua build.

Uma alternativa ativa em 2026 e `Raphire/Win11Debloat`, que continua recebendo releases e suporta Windows 10/11:

https://github.com/Raphire/Win11Debloat

Nao troque de ferramenta apenas porque e mais nova: revise exatamente o que cada preset remove ou altera.

## Antes de executar

- Windows Update e drivers prontos;
- backup feito;
- ponto de restauracao quando aplicavel;
- conferir build do Windows;
- entender o que o preset remove;
- nao remover componente so por ele parecer 'bloat'.

O objetivo e reduzir lixo, nao criar um Windows fragil e impossivel de manter.
