# Agente administrativo

Conta Windows **Administrator** opcional e exclusiva para automação administrativa excepcional.

Esse papel funciona como acesso de emergência para instalar ou configurar componentes globais, Hyper-V, WSL, drivers, serviços, PATH da máquina, rede e reparos administrativos.

Quando o agente for Codex, `config/codex-god.toml` pode ser usado como base para a configuração local da conta.

Restrições:

- nunca salvar a senha em script;
- não usar `runas /savecred`;
- não usar essa conta em tarefas comuns de código;
- não abrir repositórios desconhecidos com acesso total;
- não manter uma sessão administrativa aberta sem necessidade;
- manter uma conta humana de recuperação independente.
