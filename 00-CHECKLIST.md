# Checklist de instalação

## Mídia do Windows

- [ ] Seguir [`imagem-windows/README.md`](imagem-windows/README.md).
- [ ] Usar uma mídia oficial do Windows sem alterar `boot.wim` ou `install.wim`.
- [ ] Manter `autounattend.xml` ausente ou usar somente o modelo opcional fornecido pelo projeto.
- [ ] Confirmar que não existe uma pasta `Installers` na mídia.
- [ ] Copiar `Validar-Midia.cmd` e `Validar-Midia.ps1` para a raiz da mídia.
- [ ] Executar `Validar-Midia.cmd` na mídia antes de iniciar a instalação.
- [ ] Manter as telas de escolha de edição, disco, partição e conta.

## Preparação manual

- [ ] Windows 11 Pro instalado e ativado.
- [ ] Windows Update concluído.
- [ ] Drivers instalados e Gerenciador de Dispositivos revisado.
- [ ] UEFI, Secure Boot, TPM e virtualização habilitados quando suportados.
- [ ] Proteção do Sistema habilitada manualmente no volume do Windows.
- [ ] Espaço reservado para pontos de restauração.
- [ ] Segundo disco, quando usado, com exatamente um volume NTFS saudável.
- [ ] `config/machine.psd1` revisado.

## Plano

- [ ] Para o fluxo simples, dar duplo clique em `INSTALAR.cmd`, aceitar o UAC e conferir o plano mostrado.
- [ ] Se preferir executar manualmente, seguir os comandos abaixo.
- [ ] Abrir Windows PowerShell 5.1 como Administrador.
- [ ] Executar `Set-ExecutionPolicy -Scope Process Bypass`.
- [ ] Executar `.\bootstrap.ps1 -Config .\config\machine.psd1 -Plan`.
- [ ] Conferir a raiz de dados escolhida.
- [ ] Conferir usuários, recursos, permissões e pacotes.
- [ ] Ler o relatório informado pelo comando.

## Aplicação

- [ ] Executar `.\bootstrap.ps1 -Config .\config\machine.psd1 -Apply`.
- [ ] Informar senhas somente no prompt seguro.
- [ ] Se solicitado, reiniciar e executar o mesmo comando `-Apply`.
- [ ] Confirmar que a aplicação terminou com relatório `Completed`.
- [ ] Testar o login da conta de recuperação antes de rebaixar manualmente o usuário diário.

## Validação

- [ ] Executar `.\verify.ps1 -Config .\config\machine.psd1` como Administrador.
- [ ] Corrigir itens `FAIL`.
- [ ] Revisar itens `WARN`.
- [ ] Testar Windows Update, Microsoft Store, rede, áudio e jogos.
- [ ] Testar WSL e Docker após o primeiro login/configuração necessária.
- [ ] Guardar os relatórios de `%ProgramData%\pc-setup\reports`.

## Opcional

- [ ] Ler `docs/DEBLOAT.md` antes de habilitar o debloat.
- [ ] Configurar plano de fundo somente com uma imagem revisada no projeto.
- [ ] Criar e testar a VM pública antes de habilitar a conta/lançador.
