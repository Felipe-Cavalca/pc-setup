# Agente padrão

Conta Windows **Standard** exclusiva para ferramentas de automação ou agentes de código.

Pode trabalhar no diretório `Development` configurado, alterar código, executar builds e testes, usar containers permitidos e criar commits.

Não deve acessar `PersonalData`, chaves pessoais, credenciais do usuário diário ou configurações administrativas do host.

Quando o agente for Codex, `config/codex-standard.toml` pode ser usado como base para a configuração local da conta. Credenciais Git remotas devem ser próprias da conta do agente.

Fluxo esperado:

```text
git status
-> branch e alteração
-> build
-> testes
-> revisão do diff
-> commit autorizado
```

Tarefas que alterem o host exigem uma conta administrativa apropriada e autorização explícita.
