# Papéis de usuário

As contas do Windows são definidas em `config\machine.psd1`. Nomes podem ser alterados; o projeto depende dos papéis e privilégios configurados, não de nomes específicos.

| Papel | Chave de configuração | Privilégio | Finalidade |
|---|---|---|---|
| Usuário diário | `Accounts.DailyUser` | Standard após validação | Navegação, jogos e trabalho pessoal |
| Administrador de recuperação | `Accounts.RecoveryAdmin` | Administrator | Manutenção e recuperação manual |
| Agente padrão | `Accounts.Codex` | Standard | Código, testes e containers sem administrar o host |
| Agente administrativo | `Accounts.God` | Administrator | Automação administrativa excepcional |
| Usuário público | `Accounts.Public` | Standard | Acesso restrito a uma VM dedicada |

Contas opcionais permanecem desabilitadas até serem habilitadas explicitamente no perfil. Senhas são solicitadas em prompt seguro e não devem ser armazenadas no Git.

O usuário diário só deve perder privilégios administrativos depois que a conta de recuperação for testada. Contas de agentes não devem acessar dados pessoais ou credenciais do usuário principal. A conta pública deve permanecer isolada dos dados do host e servir apenas como entrada para uma VM dedicada.
