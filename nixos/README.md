# NixOS — NP55XDA-KF2BR

Configuração declarativa do NixOS para o notebook do Felipe, mantendo Windows em dual boot.

## Objetivo

- NixOS 26.05 + GNOME.
- Windows preservado no NVMe de 256 GB.
- NixOS instalado **no mesmo NVMe de 256 GB**, usando apenas espaço não alocado criado a partir da partição do Windows.
- NVMe de 1 TB (dados / antigo `D:`) **não deve ser particionado, formatado nem usado como destino da instalação**.
- Setup reproduzível via Flakes.

## Hardware conhecido

- Modelo informado: Samsung NP55XDA-KF2BR.
- RAM: 24 GB (8 GB + 16 GB).
- Disco do sistema: NVMe 256 GB, atualmente com Windows.
- Disco de dados: NVMe 1 TB, deve permanecer intacto.

## Antes de instalar

1. No Windows, faça backup dos dados importantes.
2. Desative a Inicialização Rápida do Windows.
3. Se BitLocker estiver ativo no disco do sistema, salve a chave de recuperação antes de alterar partições.
4. Pelo Gerenciamento de Disco do Windows, reduza **somente a partição C:** para criar espaço não alocado para o NixOS.
5. **Não reduza, exclua ou formate nenhuma partição do disco de 1 TB.**
6. Reinicie pelo instalador do NixOS em modo UEFI.

Uma divisão inicial razoável para o NVMe de 256 GB é deixar cerca de 80–120 GB para o NixOS, se o espaço do Windows permitir. Não há swap em partição neste setup; o sistema usa zram.

## Identificar os discos antes de qualquer alteração

No instalador:

```bash
lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,MOUNTPOINTS
sudo nvme list
```

Confirme pelo **tamanho e modelo**, não apenas por nomes como `/dev/nvme0n1`, porque a ordem dos NVMe pode mudar entre boots.

O disco de 1 TB deve ser tratado como somente leitura durante o particionamento: nenhuma partição dele deve ser criada, apagada ou formatada.

## Particionamento

Use particionamento manual no espaço não alocado do NVMe de 256 GB.

Recomendado:

- Reutilizar a ESP/EFI existente do Windows como `/boot`, **sem formatá-la**.
- Criar uma única partição Linux no espaço não alocado para `/` (ext4 ou btrfs).
- Não criar swap em disco; `zramSwap` já está habilitado.

O `systemd-boot` é configurado pelo NixOS. Com o Windows Boot Manager presente na mesma máquina UEFI, ele continua disponível para dual boot.

## Instalação

Depois de montar `/mnt` e `/mnt/boot` corretamente:

```bash
sudo nixos-generate-config --root /mnt
```

Clone este repositório dentro do sistema montado ou copie a pasta `nixos` para um local persistente. Em seguida, substitua:

```text
nixos/hosts/np55xdakf2br/hardware-configuration.nix
```

pelo arquivo gerado em:

```text
/mnt/etc/nixos/hardware-configuration.nix
```

Esse passo é obrigatório: UUIDs e filesystems não são inventados nem armazenados previamente no repositório.

Instale usando o flake:

```bash
cd /caminho/para/pc-setup/nixos
sudo nixos-install --flake .#np55xdakf2br
```

Defina a senha do usuário após a instalação se necessário:

```bash
sudo nixos-enter --root /mnt -c 'passwd felipe'
```

## Atualizar a máquina depois

```bash
cd ~/Dev/pc-setup/nixos
nix flake update
sudo nixos-rebuild switch --flake .#np55xdakf2br
```

Para testar antes de tornar permanente:

```bash
sudo nixos-rebuild test --flake .#np55xdakf2br
```

## Programas migrados do setup Windows

### Uso geral

- Google Chrome
- Brave
- Bitwarden
- Yubico Authenticator
- Firefox
- VLC
- LibreOffice
- Flatpak
- rclone para integração com Google Drive

WinRAR foi substituído por `p7zip`/ferramentas nativas. O Google não fornece cliente oficial do Google Drive para Linux, então o setup usa `rclone` como base.

### Desenvolvimento

- Git
- GitHub CLI
- PowerShell
- VS Code
- Docker + Docker Compose
- PHP + Composer
- Go
- Node.js
- Python
- jq / yq
- ripgrep / fd / fzf
- direnv + nix-direnv

### Jogos

- Steam
- Heroic Games Launcher (Epic/GOG)
- GameMode
- MangoHud

## Proton

O serviço Flatpak está habilitado. Proton Mail/VPN podem ser instalados por Flatpak quando essa for a opção Linux mais atual/adequada. Eles não são colocados como dependência crítica do sistema para evitar quebrar um rebuild caso o nome ou empacotamento upstream mude.

## Segurança do disco de dados

Este repositório propositalmente **não contém**:

- `disko`;
- comandos `wipefs`;
- comandos automáticos de `parted`/`fdisk`;
- UUID do NVMe de 1 TB;
- montagem obrigatória do disco de dados.

Depois que o NixOS estiver funcionando, o disco de 1 TB pode ser montado explicitamente, inclusive se estiver em NTFS, mas isso deve ser configurado somente após identificar o UUID correto da partição existente.

## Estrutura

```text
nixos/
├── flake.nix
├── hosts/
│   └── np55xdakf2br/
│       ├── configuration.nix
│       └── hardware-configuration.nix
└── modules/
    ├── base.nix
    ├── desktop.nix
    ├── development.nix
    └── gaming.nix
```
