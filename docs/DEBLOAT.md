# Debloat

## Origem da ideia

No **Akitando #114 (2022)**, Fabio Akita recomenda fazer debloat depois de uma instalacao limpa do Windows e cita o projeto do LeDragoX.

Esse projeto (`LeDragoX/Win-Debloat-Tools`) foi arquivado em 2025 e ficou limitado a builds antigas do Windows 11. A ideia continua valida; a ferramenta original nao e mais a melhor base para uma instalacao nova em 2026.

## Windows alvo deste setup

Para este PC existente, o target e:

```text
Windows 11 Pro 25H2
Build 26200+
```

A Microsoft tambem possui Windows 11 26H1, mas essa versao foi criada para novos dispositivos lancados em 2026 e nao e oferecida como feature update para PCs existentes em 24H2/25H2. Portanto nao faz sentido forcar 26H1 nesta maquina.

## Ferramenta atual

Usamos:

```text
Raphire/Win11Debloat
Release: 2026.07.11
```

Essa release continua mantida em 2026 e possui suporte explicito a recursos do Windows build 26200/25H2, incluindo opcoes especificas para o Start Menu atual.

Repositorio:

https://github.com/Raphire/Win11Debloat

## Por que uma release fixa

O metodo rapido oficial do Win11Debloat baixa e executa a versao corrente pela internet. Para um setup reproduzivel, este repo nao faz isso.

`scripts/50-debloat-akita.ps1` baixa especificamente:

```text
https://github.com/Raphire/Win11Debloat/archive/refs/tags/2026.07.11.zip
```

Assim uma reinstalacao futura nao executa silenciosamente um debloat diferente daquele documentado aqui.

Quando for decidido atualizar a versao do Win11Debloat, a alteracao deve ser feita neste repo e revisada como qualquer outra mudanca de configuracao.

## O que roda automaticamente

O script executa:

```powershell
Win11Debloat.ps1 -RunDefaults -Silent -CreateRestorePoint
```

Isso aplica o preset padrao mantido pelo projeto e remove a selecao padrao de aplicativos considerados bloatware.

Entre os defaults atuais estao tweaks para:

- telemetria e tracking;
- tips, ads e sugestoes do Windows;
- Bing/Copilot na busca;
- Microsoft Copilot;
- Windows Recall;
- Click to Do e componentes AI selecionados;
- widgets;
- exibicao de extensoes de arquivo;
- outros ajustes definidos pelo preset upstream.

O script **nao passa `-RemoveGamingApps`**. Nao queremos desabilitar deliberadamente Xbox App/Game Bar/Gaming Services em um PC que tambem sera usado para jogos.

## Aplicativos removidos

`-RunDefaults` tambem remove a lista padrao de apps definida pelo Win11Debloat. Ela muda apenas quando atualizamos a release fixada neste repositorio.

Antes de alterar a release, revisar:

- `Config/Apps.json`;
- `Config/DefaultSettings.json`;
- changelog da release.

Se futuramente algum app padrao fizer falta, podemos trocar para uma configuracao exportada propria do Win11Debloat em vez de usar o preset upstream.

## Windows PowerShell 5.1

A release 2026.07.11 recusa execucao pelo PowerShell 7. Por isso nosso wrapper detecta PowerShell Core e relanca automaticamente o debloat pelo **Windows PowerShell 5.1**.

## Executar

Depois de Windows Update e drivers:

```powershell
.\scripts\50-debloat-akita.ps1
```

O processo e automatizado e silencioso depois de iniciado.

## Antes de executar

- Windows 11 Pro 25H2 atualizado;
- drivers instalados;
- backup feito;
- BitLocker/recovery keys guardados;
- nenhum trabalho importante aberto;
- preferencialmente antes de instalar todo o software pessoal.

## Depois

1. reiniciar o Windows;
2. executar `verify.ps1`;
3. confirmar Windows Update;
4. testar Microsoft Store;
5. testar jogos/Xbox caso sejam usados;
6. conferir Device Manager;
7. criar backup/imagem do estado limpo.

## Principio

Debloat nao e competicao para remover o maximo possivel.

O objetivo e ter uma instalacao simples, entendida e reproduzivel sem destruir componentes que voce realmente usa.
