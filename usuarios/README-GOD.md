# God

Conta Windows **Administrator** exclusiva do agente.

Pense nela como **break glass**.

Use para instalar/configurar componentes globais, Hyper-V, WSL, drivers, servicos, PATH da maquina, rede e reparos administrativos.

Config sugerida: `config/codex-god.toml` -> `C:\Users\God\.codex\config.toml`.

Nunca:

- salvar a senha em script;
- usar `runas /savecred`;
- usar God para tarefa comum de codigo;
- abrir repositorio desconhecido com full access;
- deixar uma sessao God aberta sem necessidade.

Se God causar um problema, encerre e recupere usando Admin.
