# Recuperação

O `pc-setup` interrompe em erro e registra o estado da aplicação, mas não oferece rollback transacional de toda a máquina. Antes de usar em hardware real, mantenha backup dos arquivos pessoais e teste o perfil em VM.

Com `Runtime.ExecutionLogEnabled = $true`, a janela mostra o caminho do log `execution-*.jsonl` em `%LOCALAPPDATA%\pc-setup\reports`. Consulte suas últimas linhas para identificar a etapa e o comando externo que falharam. Valores reconhecidos como senha, token, credencial, chave ou PIN aparecem somente como `[REDACTED]`.

## O que cada proteção cobre

- ponto de restauração do Windows: arquivos de sistema, Registro, drivers e parte das configurações; não é backup de documentos, discos de VM ou distribuições WSL;
- checkpoint de VM: melhor forma de repetir o teste integral do instalador;
- backup de ACL: permite restaurar as permissões das pastas protegidas; o rollback automático ocorre somente se a etapa de ACL falhar;
- Git ou backup externo: protege o projeto e arquivos pessoais contra exclusão, corrupção ou mudança indevida.

## Aplicação interrompida

O estado fica em `%ProgramData%\pc-setup\apply-state.json`. Depois de corrigir o erro, execute o mesmo `INSTALAR.cmd` ou `ATUALIZAR.cmd`. A retomada só é aceita quando configuração, scripts, raiz de dados e ponto de restauração continuam correspondendo à aplicação interrompida.

Depois que a fase Windows termina, `%LOCALAPPDATA%\pc-setup\user-reconcile-state.json` permite retomar pacotes, personalização e WSL sem reaplicar a máquina. Os scripts dessa fase recusam execução sem o relatório Windows concluído e protegido da mesma configuração. O perfil padrão aceita esse comprovante por no máximo 24 horas; depois disso, uma nova fase Windows protegida é exigida.

Não edite o arquivo de estado manualmente. Se o projeto ou a configuração mudou, preserve o relatório de falha e gere um novo plano. Remover um estado incompleto é uma decisão manual: faça isso apenas depois de verificar quais etapas foram aplicadas, pois o projeto converge de forma aditiva e não desfaz automaticamente alterações concluídas.

## Winget sem acesso à fonte padrão

Se a instalação de um pacote mostrar `Failed to open the predefined source`, `0x80070005` ou `Acesso negado`, permaneça conectado na conta diária configurada e abra o PowerShell normalmente, sem usar **Executar como administrador**. Execute:

```powershell
winget source list
winget source update --name winget
```

Se a atualização terminar corretamente, execute novamente `INSTALAR.cmd` ou `ATUALIZAR.cmd`. A fase da conta diária será retomada do estado salvo; não é necessário recriar a VM nem repetir a instalação do Windows.

As fontes e o App Installer pertencem ao perfil que executa o Winget. Não use primeiro `winget source reset --force` em um PowerShell aberto com as credenciais de outra conta administrativa, pois isso pode reparar o perfil errado. Se `winget source update` continuar retornando acesso negado, atualize ou repare o **App Installer** pela Microsoft Store na conta diária antes de tentar novamente.

`--accept-source-agreements` deve ser usado em comandos como `list`, `install` e `upgrade`; ele não é uma opção de `winget source update`. O `pc-setup` consulta explicitamente apenas a fonte `winget`, portanto não depende da aceitação dos termos da fonte `msstore`.

Antes de processar os pacotes, o `pc-setup` atualiza automaticamente a fonte `winget` da conta diária. Os comandos acima permanecem úteis para diagnóstico manual caso o App Installer não consiga concluir essa atualização.

O código `0x80072ee7`, acompanhado por `InternetOpenUrl() failed`, indica falha de resolução de nome ou conectividade, não ausência do pacote. Confirme que o navegador abre `https://cdn.winget.microsoft.com`, verifique data e hora, DNS, proxy ou VPN e execute novamente:

```powershell
winget source update --name winget
```

Depois, repita `INSTALAR.cmd` ou `ATUALIZAR.cmd`. Não é necessário recriar a VM. O setup não transforma uma falha de rede em download alternativo sem hash; se não existir fallback offline configurado para o pacote, ele interrompe com segurança.

O Winget não é reiniciado com outra conta administrativa, pois as fontes e o App Installer pertencem ao perfil diário. O perfil padrão usa o instalador `user` do PowerShell. Instaladores `machine` que conseguem elevar a si mesmos ainda podem abrir UAC; se o próprio comando Winget exigir contexto administrativo, a tentativa online termina com diagnóstico e o fallback offline configurado é avaliado.

## ACLs

Os backups ficam em `%ProgramData%\pc-setup\acl-backups`. Cada execução contém `manifest.json` e arquivos aceitos por `icacls /restore`. Prefira restaurar somente a execução e a pasta afetadas, em um Windows PowerShell elevado, depois de conferir os caminhos no manifesto.

## Backup de arquivos pessoais

`BACKUP.cmd` cria um snapshot local datado das origens configuradas e valida seu manifesto SHA-256. O snapshot fica em `Storage.Paths.Backups`, no mesmo armazenamento da raiz de dados; ele é uma área de preparação, não protege contra falha ou perda desse disco.

Conecte a unidade externa somente quando necessário e execute `EXPORTAR-BACKUP.cmd`. O destino é solicitado quando `Backup.ExternalDestination` está vazio, a cópia fica sob `pc-setup-backups` e é verificada antes de ser declarada concluída. Uma pasta sincronizada pelo Google Drive pode ser informada manualmente, mas o cliente de sincronização e suas credenciais permanecem fora do script. `VERIFICAR-BACKUP.cmd` confere novamente o snapshot local mais recente.

`TESTAR-RESTAURACAO.cmd` faz uma restauração completa do snapshot mais recente em `Backup.RestoreTest.Destination`, confere todos os hashes e grava um relatório em `%LOCALAPPDATA%\pc-setup\reports`. Com `KeepRestoredCopy = $false`, somente a cópia temporária validada é removida; o snapshot nunca é apagado. Em caso de falha, a cópia incompleta é preservada para diagnóstico.

## WSL

Se a instalação mostrar um caminho como `wslpath: C:pc-setup-mainwsllinuxbootstrap.sh`, o Ubuntu já foi instalado; a falha ocorreu somente na conversão do caminho Windows. Use uma versão do projeto que execute `wslpath` por `wsl.exe --exec` e rode novamente `INSTALAR.cmd` ou `ATUALIZAR.cmd` na conta diária. A reconciliação é idempotente e retoma o ambiente, portanto não é necessário recriar a VM nem reinstalar a distribuição.

Se `DailyUser` passar e o ambiente `Agent` terminar com `Unknown argument: true`, atualize o projeto para uma versão que omita argumentos SHA-256 vazios ao chamar o WSL e execute `ATUALIZAR.cmd` novamente. O usuário diário e a distribuição já configurados são reaproveitados; não recrie a VM nem remova o Ubuntu.

Antes de mudanças importantes em uma distribuição existente:

```powershell
wsl.exe --shutdown
wsl.exe --export Ubuntu-24.04 D:\Backups\Ubuntu-24.04.tar
```

O arquivo exportado contém todo o filesystem da distribuição, inclusive homes, credenciais do harness, token e dados do `ai-memory`. Proteja-o como dado sensível. A importação deve ser feita manualmente em outro nome ou depois de confirmar a substituição da distribuição afetada.

## Máquina virtual

Para validar o fluxo completo, crie um checkpoint antes de executar `INSTALAR.cmd`, teste reinícios, atualização, conta Admin, conta diária, conta pública e WSL e então restaure o checkpoint. O roteiro está em [`../imagem-windows/docs/TESTE-EM-VM.md`](../imagem-windows/docs/TESTE-EM-VM.md).

## Quando restaurar o Windows

Use a interface de Recuperação do Windows para selecionar o ponto registrado no relatório `pc-setup-apply-*.json`. A restauração do sistema é a última opção para alterações de máquina; pacotes, arquivos pessoais e WSL ainda precisam ser conferidos separadamente.
