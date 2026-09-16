# pc-setup — NixOS

Esta branch (`nix`) contém a configuração declarativa do NixOS para o notebook Samsung NP55XDA-KF2BR.

O estado anterior do Windows está preservado em **dois pontos independentes** no GitHub:

- branch `windows`;
- tag `windows`.

Ambos apontam para o último commit da `main` antes da migração.

## Objetivos

- NixOS 26.05 + GNOME;
- dual boot com Windows no NVMe de 256 GB;
- **nenhuma alteração automática no NVMe de 1 TB / antigo D:**;
- usuário diário sem privilégios administrativos gerais;
- conta administrativa separada;
- ambiente de desenvolvimento reproduzível;
- Steam + Heroic;
- Docker rootless;
- KVM/libvirt;
- Codex isolado em usuário próprio com `ai-jail` e `ai-memory`;
- configuração de usuário via Home Manager.

A instalação é deliberadamente manual na etapa de particionamento. Não há `disko`, `wipefs`, `fdisk` ou qualquer rotina que escolha discos automaticamente.

Veja [`nixos/README.md`](nixos/README.md) antes de instalar.
