# Personalização do Windows

O personalizador converge a aparência e as pastas da conta diária sem misturar essas decisões com o debloat geral.

## Como executar

- `INSTALAR.cmd`: aplica automaticamente quando `ApplyOnInstall = $true`;
- `ATUALIZAR.cmd`: pergunta antes de reaplicar quando `PromptOnUpdate = $true`;
- `PERSONALIZAR.cmd`: mostra somente o plano de personalização, pede `S`, solicita a credencial administrativa para o ponto de restauração e aplica a etapa.

Execute o launcher manual na conta configurada em `Accounts.DailyUser.Name`. O Explorador do Windows é reiniciado no final; a barra de tarefas pode desaparecer por alguns segundos.

## Perfil padrão

O perfil versionado:

- usa o tema escuro;
- oculta a caixa de pesquisa e o botão Visão de Tarefas;
- limpa os aplicativos fixados no menu Iniciar e mantém a possibilidade de fixar itens depois;
- seleciona a visualização “Todos” em categorias;
- deixa somente Configurações junto ao botão de energia;
- desabilita o início rápido e o modo em segundo plano do Edge e remove entradas de inicialização do perfil;
- desinstala o OneDrive sem apagar a pasta de dados que já existia e oculta o atalho residual do Explorador;
- remove o aplicativo LinkedIn do perfil diário;
- não remove Vincular ao Celular nem o componente Cross Device.

A limpeza dos fixados usa o `start2.bin` vazio da versão do Win11Debloat já fixada e validada por SHA-256 no projeto. O estado anterior recebe uma cópia em `%LOCALAPPDATA%\pc-setup\backups\start-menu`.

A visualização por categoria depende da implementação presente nas builds recentes do Windows 11. Em versões que ainda não oferecem esse modo, o Registro pode aceitar a configuração sem alterar a interface até a atualização do Windows.

## Pastas pessoais

As pastas declaradas em `KnownFolders` passam a apontar para subpastas de `Storage.Paths.PersonalData`. No padrão:

```text
<raiz de dados>\Data\<usuário>\Desktop
<raiz de dados>\Data\<usuário>\Documents
<raiz de dados>\Data\<usuário>\Downloads
<raiz de dados>\Data\<usuário>\Music
<raiz de dados>\Data\<usuário>\Pictures
<raiz de dados>\Data\<usuário>\Videos
```

O script usa a API de pastas conhecidas do Windows. Antes de redirecionar, copia o conteúdo existente com `robocopy`, sem seguir junções e sem excluir a origem. Depois de conferir o resultado, a cópia antiga pode ser removida manualmente.

Esse mecanismo não muda automaticamente os diretórios internos de Docker, Steam ou Epic. Eles continuam documentados como integrações próprias porque cada aplicativo possui seu formato e seu ciclo de vida.

## Plano de fundo

Coloque a imagem em `config\wallpapers` e informe o caminho relativo:

```powershell
WallpaperPath = 'config\wallpapers\minha-imagem.jpg'
```

Com `WallpaperPath = ''`, todo o restante é aplicado e o plano de fundo atual é preservado.

## Aplicativos Proton

`Proton.ProtonMail` e `Proton.ProtonVPN` estão no perfil `base` como pacotes opcionais do Winget. O instalador tenta obter a versão atual; uma falha nesses itens fica como pendência e não interrompe sozinha o setup.
