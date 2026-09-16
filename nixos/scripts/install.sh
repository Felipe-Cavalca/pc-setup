#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'ERRO: %s\n' "$*" >&2
  exit 1
}

need_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "execute este script com sudo/root."
}

mount_source() {
  findmnt -nr -o SOURCE -M "$1" 2>/dev/null || return 1
}

mount_fstype() {
  findmnt -nr -o FSTYPE -M "$1" 2>/dev/null || return 1
}

parent_disk() {
  local source resolved type parent

  source="$(mount_source "$1")" || return 1
  resolved="$(readlink -f -- "$source")"
  type="$(lsblk -ndo TYPE "$resolved" 2>/dev/null | head -n1)"

  if [[ $type == disk ]]; then
    printf '%s\n' "$resolved"
    return 0
  fi

  [[ $type == part ]] || return 1
  parent="$(lsblk -ndo PKNAME "$resolved" 2>/dev/null | head -n1)"
  [[ -n $parent ]] || return 1
  printf '/dev/%s\n' "$parent"
}

part_type() {
  local source resolved
  source="$(mount_source "$1")" || return 1
  resolved="$(readlink -f -- "$source")"
  lsblk -ndo PARTTYPE "$resolved" 2>/dev/null | head -n1 | tr '[:upper:]' '[:lower:]'
}

need_root

for target in /mnt /mnt/boot /mnt/efi; do
  mountpoint -q "$target" || die "$target precisa estar montado antes da instalação."
done

root_disk="$(parent_disk /mnt)" || die "não consegui identificar o disco de /mnt."
boot_disk="$(parent_disk /mnt/boot)" || die "não consegui identificar o disco de /mnt/boot."
efi_disk="$(parent_disk /mnt/efi)" || die "não consegui identificar o disco de /mnt/efi."

[[ $root_disk == "$boot_disk" && $root_disk == "$efi_disk" ]] ||
  die "/, /boot e /efi precisam estar no MESMO disco físico."

disk_size="$(lsblk -bdno SIZE "$root_disk" | head -n1)"
[[ $disk_size =~ ^[0-9]+$ ]] || die "não consegui ler o tamanho de $root_disk."

max_bytes=$((400 * 1024 * 1024 * 1024))
(( disk_size <= max_bytes )) ||
  die "$root_disk é maior que 400 GiB; recusando para proteger o disco de 1 TB."

[[ "$(mount_fstype /mnt/boot)" == vfat ]] ||
  die "/mnt/boot deve ser a nova partição FAT32 XBOOTLDR."

[[ "$(mount_fstype /mnt/efi)" == vfat ]] ||
  die "/mnt/efi deve ser a ESP FAT32 existente do Windows."

xbootldr_guid='bc13c2ff-59e6-4262-a352-b275fd6f7172'
esp_guid='c12a7328-f81f-11d2-ba4b-00a0c93ec93b'

[[ "$(part_type /mnt/boot)" == "$xbootldr_guid" ]] ||
  die "/mnt/boot não está marcada como GPT XBOOTLDR (Linux extended boot)."

[[ "$(part_type /mnt/efi)" == "$esp_guid" ]] ||
  die "/mnt/efi não está marcada como EFI System Partition."

[[ "$(mount_source /mnt/boot)" != "$(mount_source /mnt/efi)" ]] ||
  die "/boot deve ser a nova XBOOTLDR; não use a pequena ESP do Windows para os kernels."

[[ -f /mnt/efi/EFI/Microsoft/Boot/bootmgfw.efi ]] ||
  die "Windows Boot Manager não encontrado em /mnt/efi; confirme que esta é a ESP correta."

while read -r source target; do
  [[ $source == /dev/* ]] || continue
  resolved="$(readlink -f -- "$source")"
  [[ "$(lsblk -ndo TYPE "$resolved" 2>/dev/null | head -n1)" == part ]] || continue
  parent="$(lsblk -ndo PKNAME "$resolved" 2>/dev/null | head -n1)"
  [[ -n $parent ]] || continue
  [[ "/dev/$parent" == "$root_disk" ]] ||
    die "$target vem de /dev/$parent, diferente do disco de sistema $root_disk."
done < <(findmnt -R -nr -o SOURCE,TARGET /mnt)

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
nixos_dir="$(cd -- "$script_dir/.." && pwd)"
hardware="$nixos_dir/hosts/np55xdakf2br/hardware-configuration.nix"

printf 'Disco autorizado: %s\n' "$root_disk"
lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,PARTTYPE,MOUNTPOINTS "$root_disk"
printf '\nO disco de 1 TB não será usado pelo instalador.\n'

nixos-generate-config --root /mnt --show-hardware-config > "$hardware"

printf '\nHardware real salvo em:\n  %s\n\n' "$hardware"

nixos-install \
  --flake "$nixos_dir#np55xdakf2br" \
  --no-root-passwd

printf '\nDefina as senhas locais. A conta root permanece bloqueada.\n'
for user in felipe admin publico; do
  printf '\nSenha para %s:\n' "$user"
  nixos-enter --root /mnt -c "passwd $user"
done

sync

cat <<'EOF'

Instalação concluída.

Após reiniciar:
  1. Entre como felipe.
  2. Para administração, use a conta admin.
  3. O setup versionado está em /etc/pc-setup se você clonou o repositório lá.
  4. Faça login do Codex para o usuário agent na primeira vez usando `agente`.
  5. Não configure o disco de 1 TB até confirmar seu UUID e o que deseja montar.

EOF
