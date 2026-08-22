# Auditoria da instalação atual

Data da auditoria: 22 de agosto de 2026.

## Conclusão

O arquivo de resposta antigo teve eficácia real, mas parcial. Ele foi usado pela instalação atual e vários scripts foram executados. Os downloads de plano de fundo e Chrome falharam porque a rede não estava disponível durante a fase `specialize`.

Por isso, os arquivos antigos não devem ser reutilizados. A mídia nova fica limitada à instalação do Windows e o `pc-setup` assume toda a pós-instalação depois do primeiro login.

## Evidências

- `C:\Windows\Panther\unattend-original.xml` tem o mesmo tamanho e SHA-256 do backup `2026-08-17_autounattend.xml.bkp` da Área de Trabalho. Isso confirma que o arquivo antigo foi carregado pelo Windows Setup em 22 de dezembro de 2025.
- `C:\Windows\Setup\Scripts` contém os scripts extraídos e os logs de `Specialize`, `DefaultUser`, `FirstLogon`, remoção de pacotes, capacidades e recursos.
- `Specialize.log` registra várias alterações concluídas e também falhas de DNS para `i.pinimg.com` e `dl.google.com`.
- Depois da falha do download do Chrome, a tentativa de iniciar o instalador também falhou porque o arquivo não existia.
- O arquivo atualmente no pendrive é diferente do usado nessa instalação. Ele foi alterado em 17 de agosto de 2026 e ainda contém quatro arquivos embutidos e comandos nas fases `specialize` e `oobeSystem`.

## Riscos encontrados no desenho antigo

- dependência de internet antes de a rede estar garantida;
- instalação de programas escondida dentro do XML;
- habilitação de recursos opcionais fora do plano e dos relatórios do projeto;
- alteração para impedir criptografia automática fora da configuração central;
- ausência do ponto de restauração obrigatório antes dessas mudanças;
- lógica duplicada entre a mídia e o repositório.

O arquivo antigo também continha campo de chave de produto. Nenhuma chave, senha, token ou conteúdo pessoal foi copiado para este repositório.

## O que foi preservado

- instalação manual do Windows 11 Pro;
- telas de escolha de disco, partições e conta;
- opção de idioma pt-BR sem automatizar ações destrutivas;
- instaladores online atuais pelo Winget no pós-instalação;
- fallback offline somente quando o arquivo constar no manifesto e o SHA-256 conferir;
- relatório, validação, retomada após reinício e ponto de restauração no `pc-setup`.
