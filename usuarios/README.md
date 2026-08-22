# Papéis de usuário

As contas do Windows são definidas em `config\machine.psd1`. Nomes podem ser alterados; o projeto depende dos papéis e privilégios configurados, não de nomes específicos.

| Papel | Chave de configuração | Privilégio | Finalidade |
|---|---|---|---|
| Usuário diário | `Accounts.DailyUser` | Standard após validação | Navegação, jogos e trabalho pessoal |
| Administrador de recuperação | `Accounts.RecoveryAdmin` | Administrator | Manutenção e recuperação manual |
| Agente padrão | `Accounts.Codex` | Standard | Código, testes e containers sem administrar o host |
| Agente administrativo | `Accounts.God` | Administrator | Automação administrativa excepcional |
| Usuário público | `Accounts.Public` | Standard | Acesso restrito a uma VM dedicada |

Documentação de cada papel:

- [`README-USUARIO-DIARIO.md`](README-USUARIO-DIARIO.md);
- [`README-ADMIN-RECUPERACAO.md`](README-ADMIN-RECUPERACAO.md);
- [`README-AGENTE-STANDARD.md`](README-AGENTE-STANDARD.md);
- [`README-AGENTE-ADMIN.md`](README-AGENTE-ADMIN.md);
- [`README-USUARIO-PUBLICO.md`](README-USUARIO-PUBLICO.md).

Contas opcionais permanecem desabilitadas até serem habilitadas explicitamente no perfil. Senhas são solicitadas em prompt seguro e não devem ser armazenadas no Git.
