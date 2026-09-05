#!/usr/bin/env bash
set -euo pipefail

profile_name=''
linux_user=''

usage() {
  printf 'Usage: prepare-ai-memory-upgrade.sh --profile-name NAME --linux-user USER\n'
}

while (($# > 0)); do
  case "$1" in
    --profile-name) profile_name="${2:-}"; shift 2 ;;
    --linux-user) linux_user="${2:-}"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  printf 'prepare-ai-memory-upgrade.sh must run as root inside WSL.\n' >&2
  exit 1
fi
if [[ ! $profile_name =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]]; then
  printf 'Invalid profile name.\n' >&2
  exit 2
fi
if [[ ! $linux_user =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  printf 'Invalid Linux user.\n' >&2
  exit 2
fi

# On a fresh WSL install the bootstrap creates the user later. There is no
# pre-existing ai-memory data to migrate, so the preparation can safely wait
# for the second invocation after the main bootstrap.
if ! id "$linux_user" >/dev/null 2>&1; then
  printf '[SKIP] ai-memory upgrade preparation: Linux user %s does not exist yet.\n' "$linux_user"
  exit 0
fi

ai_memory_home="/home/$linux_user"
ai_memory_data_directory="$ai_memory_home/.local/share/ai-memory"
ai_memory_backup_directory="$ai_memory_home/.local/share/ai-memory-backups"
ai_memory_service="pc-setup-ai-memory-${profile_name,,}.service"
ai_memory_dropin_directory="/etc/systemd/system/${ai_memory_service}.d"
ai_memory_dropin="$ai_memory_dropin_directory/10-pc-setup-backup.conf"

# ai-memory 2.0 takes a mandatory pre-migration archive outside its data
# directory. The base service protects HOME as read-only, so explicitly grant a
# private sibling directory for that archive before replacing/restarting the
# binary. This makes 1.x -> 2.x upgrades safe while preserving ProtectHome.
install --directory --owner "$linux_user" --group "$linux_user" --mode 0700 "$ai_memory_backup_directory"
install --directory --owner root --group root --mode 0755 "$ai_memory_dropin_directory"

temporary_dropin="$(mktemp)"
trap 'rm -f -- "$temporary_dropin"' EXIT
cat >"$temporary_dropin" <<EOF
[Service]
Environment=AI_MEMORY_BACKUP_DIR=$ai_memory_backup_directory
ReadWritePaths=$ai_memory_backup_directory
EOF
install --owner root --group root --mode 0644 "$temporary_dropin" "$ai_memory_dropin"

if [[ $(</proc/1/comm) == systemd ]]; then
  systemctl daemon-reload
fi

printf '[OK] ai-memory migration backup prepared: data=%s backup=%s service=%s\n' \
  "$ai_memory_data_directory" "$ai_memory_backup_directory" "$ai_memory_service"
