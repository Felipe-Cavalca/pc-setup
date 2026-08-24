# Auditoria da máquina

O perfil padrão gera `RESUMO-DA-MAQUINA.html` e `RESUMO-DA-MAQUINA.md` na Área de Trabalho ao final de uma reconciliação completa. `RESUMO-DA-MAQUINA.cmd` atualiza os arquivos sem reaplicar a configuração.

O resumo registra, quando as interfaces do Windows disponibilizam:

- versão e build do Windows 11;
- fabricante, modelo, processador, memória e versão da BIOS/UEFI;
- Secure Boot, TPM e estado informativo do BitLocker;
- suporte de virtualização usado por Hyper-V e WSL 2;
- saúde, tipo, barramento, tamanho e contadores de confiabilidade dos discos;
- dispositivos presentes com estado diferente de `OK`;
- contagens da verificação do `pc-setup`, último teste de restauração e distribuições WSL.

O JSON completo da coleta fica em `%LOCALAPPDATA%\pc-setup\reports`. Os arquivos da Área de Trabalho usam nome estável e são atualizados a cada execução; não devem ser publicados sem revisão porque podem conter nomes de usuário, caminhos, modelo de hardware e programas instalados.

## Limites

A auditoria é somente leitura. Ela não:

- atualiza BIOS, firmware ou drivers;
- configura BitLocker, TPM, Secure Boot ou YubiKey;
- executa reparos SMART;
- garante que um disco saudável não falhará;
- substitui o diagnóstico do fabricante.

Informações que exigem permissão, hardware ou cmdlet ausente aparecem como `Indisponível`. Isso não interrompe a instalação desde que os arquivos de resumo possam ser gravados.
