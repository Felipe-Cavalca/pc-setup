# Codex

Usuario Windows **Standard** exclusivo do agente.

Pode trabalhar no diretório `Development` configurado, alterar código, executar builds/testes, subir seu ambiente de containers e fazer commits.

Não deve acessar o diretório `PersonalData` configurado, chaves SSH do usuário principal ou configurações administrativas do host.

Config sugerida: `config/codex-standard.toml` -> `C:\Users\Codex\.codex\config.toml`.

Para push, use credencial Git propria do usuario Codex. Commit local nao exige credencial remota.

Para containers isolados, prefira uma distro WSL propria (`CodexDev`) com Docker Engine dentro dela. `sudo` dentro do Linux nao transforma Codex em administrador Windows.

Fluxo esperado:

```text
git status
-> branch/alteracao
-> build
-> containers
-> testes
-> revisar diff
-> commit
```

Se a tarefa exigir alterar a maquina, pare e use God.
