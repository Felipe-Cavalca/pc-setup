# NixOS — Samsung NP55XDA-KF2BR

Configuração declarativa do notebook, com Windows preservado em dual boot.

## Premissas fixas

- NixOS 26.05 + GNOME.
- RAM: 24 GB (8 + 16 GB).
- Windows continua no NVMe de 256 GB.
- NixOS também fica no NVMe de 256 GB.
- O NVMe de 1 TB, usado como antigo `D:`, **não participa da instalação**.
- Não há `disko` nem particionamento automático.
- Não há swap em disco; há zram.
- A conta diária `felipe` não pertence a `wheel`.
- A conta `admin` é a conta administrativa.
- `agent` é um usuário separado e sem senha/sudo.

## Por que `/efi` + `/boot`

Instalações do Windows frequentemente deixam uma ESP pequena. Encher essa
partição com kernels/initrds do NixOS é desnecessário.

O layout usado aqui é:

- ESP já existente do Windows -> `/efi`, **sem formatar**;
- nova partição FAT32 de 1 GiB com tipo GPT **XBOOTLDR** -> `/boot`;
- nova partição Linux com o restante do espaço reservado -> `/`.

O `systemd-boot` fica na ESP existente, enquanto gerações do NixOS ficam na
XBOOTLDR. Isso mantém o Windows Boot Manager na mesma ESP e evita usar seu
pequeno espaço para os kernels do NixOS.

## 1. Preparar no Windows

Antes de iniciar o instalador do NixOS:

1. Faça backup do que for importante.
2. Desative a Inicialização Rápida do Windows.
3. Se BitLocker estiver ativo no C:, guarde a chave de recuperação e suspenda a
   proteção antes de alterar as partições.
4. Abra **Gerenciamento de Disco**.
5. Reduza **somente C:**, no NVMe de 256 GB.
6. Deixe aproximadamente 80–120 GB como **espaço não alocado**, se houver
   espaço disponível.
7. Não reduza, exclua, formate ou converta nada no disco de 1 TB.

## 2. Identificar os discos no instalador

Inicie o NixOS em UEFI e rode:

```bash
lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,PARTTYPE,MOUNTPOINTS
sudo nvme list
```

Não confie em `nvme0n1`/`nvme1n1`: a ordem pode mudar. Identifique pelo
**tamanho, modelo e serial**.

## 3. Particionar apenas o espaço livre do disco de 256 GB

Faça isso manualmente com a ferramenta que preferir (`cfdisk`, `parted` ou
interface gráfica), sempre conferindo o disco antes de gravar.

No espaço não alocado criado a partir do C:, crie:

1. **1 GiB FAT32**, tipo GPT **Linux extended boot / XBOOTLDR**
   (`bc13c2ff-59e6-4262-a352-b275fd6f7172`);
2. o restante como partição Linux para `/` (ext4 é a opção mais simples).

Não crie partição no NVMe de 1 TB.

Formate **somente as duas partições novas**. Exemplo, substituindo os nomes
pelas partições que você acabou de criar:

```bash
sudo mkfs.fat -F 32 -n NIXBOOT /dev/<PARTICAO-XBOOTLDR>
sudo mkfs.ext4 -L NIXOS /dev/<PARTICAO-ROOT>
```

**Não execute `mkfs` na ESP existente do Windows.**

## 4. Montar

```bash
sudo mount /dev/<PARTICAO-ROOT> /mnt
sudo mkdir -p /mnt/boot /mnt/efi

sudo mount /dev/<PARTICAO-XBOOTLDR> /mnt/boot
sudo mount /dev/<ESP-EXISTENTE-DO-WINDOWS> /mnt/efi
```

Confira:

```bash
findmnt -R /mnt
ls /mnt/efi/EFI/Microsoft/Boot/bootmgfw.efi
```

O segundo comando deve encontrar o Windows Boot Manager.

## 5. Clonar esta branch no sistema que será instalado

```bash
sudo mkdir -p /mnt/etc
sudo git clone --branch nix \
  https://github.com/Felipe-Cavalca/pc-setup.git \
  /mnt/etc/pc-setup
```

## 6. Instalar com o guardrail do repositório

```bash
sudo /mnt/etc/pc-setup/nixos/scripts/install.sh
```

O script **não particiona nem formata nada**. Antes de instalar ele exige:

- `/mnt`, `/mnt/boot` e `/mnt/efi` já montados;
- os três no mesmo disco físico;
- disco físico com no máximo 400 GiB;
- `/boot` em FAT32 e marcado como XBOOTLDR;
- `/efi` em FAT32 e marcado como ESP;
- Windows Boot Manager presente em `/efi`;
- nenhum outro dispositivo físico montado abaixo de `/mnt`.

Se alguma dessas verificações falhar, ele para.

Depois das verificações ele gera o `hardware-configuration.nix` real, instala o
flake e pede as senhas de `felipe`, `admin` e `publico`.

## 7. Depois do primeiro boot

A configuração do sistema fica em:

```text
/etc/pc-setup/nixos
```

Testar uma mudança:

```bash
su - admin
nixos-rebuild test --flake /etc/pc-setup/nixos#np55xdakf2br
```

Aplicar:

```bash
nixos-rebuild switch --flake /etc/pc-setup/nixos#np55xdakf2br
```

Atualizar inputs deliberadamente:

```bash
cd /etc/pc-setup/nixos
nix flake update
nixos-rebuild test --flake .#np55xdakf2br
```

O primeiro uso gera `flake.lock`; mantenha esse arquivo versionado para que
reinstalações usem exatamente os mesmos inputs.

## O que foi migrado da `main`

### Desktop

- GNOME + GDM
- tema escuro
- wallpaper já usado no setup Windows
- Chrome
- Brave
- Firefox
- Bitwarden
- Yubico Authenticator
- VS Code
- VLC
- LibreOffice
- Flatpak

Google Drive não possui cliente oficial equivalente no Linux; `rclone` fica
instalado, mas nenhum mount é criado automaticamente.

Proton Mail/VPN ficam fora da closure crítica. Flatpak está disponível para
instalá-los quando desejado.

### Desenvolvimento

- Git + GitHub CLI
- PowerShell
- Node.js
- Go
- PHP + Composer
- Python
- jq / yq
- ripgrep / fd / fzf
- direnv + nix-direnv
- Docker **rootless**
- Docker Compose
- KVM/libvirt + virt-manager

### Jogos

- Steam
- Heroic Games Launcher, no lugar do launcher da Epic
- GameMode
- MangoHud

### Contas

- `felipe`: uso diário, sem `wheel`;
- `admin`: administração e recuperação;
- `publico`: usuário padrão;
- `agent`: usuário bloqueado para login normal e usado pelo ambiente de IA.

## Agente de IA

O flake fixa versões conhecidas de:

- Codex;
- `ai-jail`;
- `ai-memory`.

O serviço `ai-memory` roda como `agent`, somente no host local. A integração MCP
e os hooks do Codex são aplicados de forma idempotente no boot.

Para abrir o agente no projeto atual:

```bash
cd ~/Dev/meu-projeto
agente
```

Ou informar o projeto:

```bash
agente ~/Dev/meu-projeto
```

O launcher aceita apenas projetos sob `/home/felipe/Dev` ou
`/home/agent/Dev`, troca para o usuário `agent` e executa Codex dentro de
`ai-jail`.

A rede e o estado de autenticação do Codex são habilitados explicitamente.
Docker, SSH, GPU, display, X11 e demais capacidades permanecem fechados pelos
defaults do `ai-jail`. Caminhos comuns de segredo (`.env`, credenciais e
`secrets/`) são negados.

## Proteção do disco de 1 TB

O setup não contém:

- UUID do disco de 1 TB;
- `fileSystems` para ele;
- `disko`;
- `wipefs`;
- particionamento automático;
- formatação automática;
- montagem automática pelo GNOME.

Depois de tudo funcionando, ele pode ser montado manualmente e, se você quiser,
podemos criar um módulo separado **somente para leitura/montagem do volume
existente**, usando o UUID real. Isso deve ser feito depois da instalação.
