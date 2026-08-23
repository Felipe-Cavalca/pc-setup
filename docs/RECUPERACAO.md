# Recuperação

O `pc-setup` interrompe em erro e registra o estado da aplicação, mas não oferece rollback transacional de toda a máquina. Antes de usar em hardware real, mantenha backup dos arquivos pessoais e teste o perfil em VM.

## O que cada proteção cobre

- ponto de restauração do Windows: arquivos de sistema, Registro, drivers e parte das configurações; não é backup de documentos, discos de VM ou distribuições WSL;
- checkpoint de VM: melhor forma de repetir o teste integral do instalador;
- backup de ACL: permite restaurar as permissões das pastas protegidas; o rollback automático ocorre somente se a etapa de ACL falhar;
- Git ou backup externo: protege o projeto e arquivos pessoais contra exclusão, corrupção ou mudança indevida.

## Aplicação interrompida

O estado fica em `%ProgramData%\pc-setup\apply-state.json`. Depois de corrigir o erro, execute o mesmo `INSTALAR.cmd` ou `ATUALIZAR.cmd`. A retomada só é aceita quando configuração, scripts, raiz de dados e ponto de restauração continuam correspondendo à aplicação interrompida.

Depois que a fase Windows termina, `%LOCALAPPDATA%\pc-setup\user-reconcile-state.json` permite retomar pacotes, personalização e WSL sem reaplicar a máquina. Os scripts dessa fase recusam execução sem o relatório Windows concluído e protegido da mesma configuração. O perfil padrão aceita esse comprovante por no máximo 24 horas; depois disso, uma nova fase Windows protegida é exigida.

Não edite o arquivo de estado manualmente. Se o projeto ou a configuração mudou, preserve o relatório de falha e gere um novo plano. Remover um estado incompleto é uma decisão manual: faça isso apenas depois de verificar quais etapas foram aplicadas, pois o projeto converge de forma aditiva e não desfaz automaticamente alterações concluídas.

## ACLs

Os backups ficam em `%ProgramData%\pc-setup\acl-backups`. Cada execução contém `manifest.json` e arquivos aceitos por `icacls /restore`. Prefira restaurar somente a execução e a pasta afetadas, em um Windows PowerShell elevado, depois de conferir os caminhos no manifesto.

## WSL

Antes de mudanças importantes em uma distribuição existente:

```powershell
wsl.exe --shutdown
wsl.exe --export Ubuntu-24.04 D:\Backups\Ubuntu-24.04.tar
```

O arquivo exportado contém todo o filesystem da distribuição, inclusive homes e estado do agente. Proteja-o como dado sensível. A importação deve ser feita manualmente em outro nome ou depois de confirmar a substituição da distribuição afetada.

## Máquina virtual

Para validar o fluxo completo, crie um checkpoint antes de executar `INSTALAR.cmd`, teste reinícios, atualização, conta Admin, conta diária, conta pública e WSL e então restaure o checkpoint. O roteiro está em [`../imagem-windows/docs/TESTE-EM-VM.md`](../imagem-windows/docs/TESTE-EM-VM.md).

## Quando restaurar o Windows

Use a interface de Recuperação do Windows para selecionar o ponto registrado no relatório `pc-setup-apply-*.json`. A restauração do sistema é a última opção para alterações de máquina; pacotes, arquivos pessoais e WSL ainda precisam ser conferidos separadamente.
