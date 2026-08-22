# Configuração

`machine.psd1` guarda decisões não secretas e funciona como perfil versionado de referência. Ele não deve ser executado sem revisão. Os scripts não dependem de letra, modelo ou tamanho fixo de disco.

Nunca coloque no arquivo senhas, tokens, chaves de produto, certificados ou chaves de recuperação.

`INSTALAR.cmd` sempre carrega `config\machine.psd1`. Um perfil diferente pode ser usado de duas formas:

- revisar e substituir o conteúdo de `machine.psd1` em um fork próprio;
- executar manualmente `bootstrap.ps1 -Config <arquivo>` para selecionar outro `.psd1`.

## Execução

`Execution.Mode = 'Unattended'` impede perguntas de decisão durante a aplicação. Senhas de contas novas continuam sendo coletadas em prompt seguro e ficam apenas na memória.

`Runtime.RequirePlanBeforeApply = $true` exige que a configuração e a raiz de dados coincidam com o último plano salvo.

## Armazenamento

Valores de `Storage.Data.SecondaryDiskPolicy`:

- `UseIfAvailable`: usa um único volume NTFS saudável em disco fixo secundário;
- `Ask`: oferece os candidatos no modo `Interactive`;
- `Ignore`: usa a raiz configurada no volume do Windows.

`OnMultipleCandidates` permanece `Stop`. Dispositivos removíveis não participam por padrão.

Para um disco:

```powershell
Mode                = 'DirectoryOnSystemVolume'
SecondaryDiskPolicy = 'Ignore'
Root                = '{SystemRoot}\Dados'
```

Use [`examples/machine-one-disk.psd1`](examples/machine-one-disk.psd1) como ponto de partida.

## Contas

Cada entrada possui `Enabled`, `Name` e `Role`. Funções válidas: `Standard` e `Administrator`.

`Security.DemoteDailyUserAutomatically = $false` evita perder acesso administrativo antes do teste da conta de recuperação. O usuário diário só deve ser rebaixado depois que a conta administrativa configurada for validada.

Os papéis recomendados e seus limites estão documentados em [`../usuarios/README.md`](../usuarios/README.md). Os nomes presentes no perfil versionado são exemplos configuráveis, não requisitos do projeto.

## Pacotes

`Packages.Profiles` seleciona arquivos de `config/packages`. Cada linha contém um ID Winget exato.

O fallback fica em `offline-installers.psd1`. Cada entrada exige `PackageId`, caminho relativo, SHA-256 e argumentos silenciosos. O diretório padrão é `installers` na raiz do projeto.

## WSL

`DefaultVersion = 2` define o padrão global. `Distribution = ''` mantém desativado o mecanismo legado de instalação centralizada.

`WSL.Environments` descreve as distribuições registradas por conta Windows. Cada entrada informa:

- `Enabled`: se o ambiente deve ser preparado;
- `AccountKey`: chave da conta em `Accounts`;
- `Distribution`: nome aceito por `wsl --install --distribution`;
- `Profile`: PSD1 relativo ao projeto com usuário Linux, raiz de projetos e pacotes APT.

O bootstrap principal não tenta criar essas distribuições na sessão administrativa. Entre em cada conta e use `wsl\bootstrap.ps1`; consulte [`../wsl/README.md`](../wsl/README.md).

## Inventário do Winget

`Runtime.WingetInventoryPath` define o JSON estável com IDs, versões e fontes realmente encontrados depois da instalação. O arquivo é estado local gerado e não deve ser adicionado ao repositório.

## Recuperação

As proteções obrigatórias não devem ser relaxadas:

```powershell
RequireRestorePointBeforeChanges = $true
AllowExistingRestorePointReuse   = $false
AllowSameApplySessionReuse       = $true
BackupAclBeforeChanges           = $true
```

A reutilização só vale para a mesma aplicação retomada depois de reinício, com descrição, sequência e identificador validados.

## BitLocker

O padrão é somente informativo:

```powershell
ManageBitLocker       = $false
BitLockerMode         = 'DoNotConfigure'
ReportBitLockerStatus = $true
```

O setup não ativa, suspende, desativa nem exige criptografia.

## Personalização e debloat

Ambos começam desabilitados. O plano de fundo precisa estar dentro do projeto. O debloat habilitado exige SHA-256 de 64 caracteres e confirmação em comando separado.
