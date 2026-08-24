# Papéis de usuário

As contas do Windows são definidas em `config\machine.psd1`. Os nomes são configuráveis; o projeto depende dos papéis e privilégios, não de nomes fixos.

Cada conta habilitada pertence explicitamente ao grupo local `Usuários` (`S-1-5-32-545`). O setup resolve o grupo pelo SID para funcionar em qualquer idioma, habilita uma conta configurada que já exista desabilitada e valida essa associação antes de pedir a troca de sessão.

| Papel | Chave | Privilégio | Finalidade |
|---|---|---|---|
| Usuário diário | `Accounts.DailyUser` | Standard após validação | Navegação, jogos, trabalho pessoal e chamada do agente |
| Administrador de recuperação | `Accounts.RecoveryAdmin` | Administrator | Manutenção manual e recuperação de emergência |
| Usuário público | `Accounts.Public` | Standard | Navegação persistente em Edge e Chrome para terceiros autorizados |

Não existe conta Windows para a IA. A identidade usada pelo agente é o usuário Linux `agent`, criado dentro da distribuição WSL pertencente ao usuário diário.

## Usuários Linux

| Ambiente | Usuário Linux | Privilégio | Finalidade |
|---|---|---|---|
| `WSL.Environments.DailyUser` | configurável; padrão `felipe` | usuário padrão da distribuição | Desenvolvimento manual |
| `WSL.Environments.Agent` | configurável; padrão `agent` | sem `sudo`, senha bloqueada | Execução de agentes dentro do `ai-jail` |

O workspace `/home/agent/Dev` pertence a `agent:pcsetup-agent`. O usuário Linux diário também participa desse grupo para revisar e continuar o trabalho sem entrar em outra sessão do Windows.

O usuário diário só deve perder privilégios administrativos depois que a conta de recuperação for testada. No perfil padrão, ele também entra no grupo local `Hyper-V Administrators`, recebendo acesso amplo às VMs e switches do Hyper-V, mas não administração geral do Windows.

O perfil `Publico` não encerra a sessão nem apaga automaticamente os dados dos navegadores. Ele não é um quiosque: programas instalados para toda a máquina podem continuar visíveis mesmo que o uso previsto seja somente Edge e Chrome.

Depois que a associação ao grupo for aplicada, encerre e abra novamente a sessão do usuário diário para que o novo token de acesso seja usado.

Senhas, tokens e sessões de agentes não devem ser armazenados no Git. A persistência de autenticação do agente é liberada explicitamente pelo launcher e permanece no perfil Linux `agent`.
