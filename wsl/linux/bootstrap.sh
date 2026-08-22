#!/usr/bin/env bash
set -euo pipefail

profile_name=''
linux_user=''
project_root=''
packages=()

usage() {
  printf 'Usage: bootstrap.sh --profile-name NAME --linux-user USER --project-root PATH [--package NAME ...]\n'
}

while (($# > 0)); do
  case "$1" in
    --profile-name) profile_name="${2:-}"; shift 2 ;;
    --linux-user) linux_user="${2:-}"; shift 2 ;;
    --project-root) project_root="${2:-}"; shift 2 ;;
    --package) packages+=("${2:-}"); shift 2 ;;
    --help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  printf 'bootstrap.sh must run as root inside WSL.\n' >&2
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
if [[ $project_root != "/home/$linux_user/"* ]] || [[ $project_root == *'/../'* ]] || [[ $project_root == *'/..' ]]; then
  printf 'Project root must stay below /home/%s/.\n' "$linux_user" >&2
  exit 2
fi
for package in "${packages[@]}"; do
  if [[ ! $package =~ ^[a-z0-9][a-z0-9+.-]*$ ]]; then
    printf 'Invalid APT package: %s\n' "$package" >&2
    exit 2
  fi
done

resolved_project_root="$(readlink --canonicalize-missing -- "$project_root")"
if [[ $resolved_project_root != "$project_root" ]]; then
  printf 'Project root must not contain symlinks or non-canonical components: %s\n' "$project_root" >&2
  exit 2
fi

if ! getent group "$linux_user" >/dev/null 2>&1; then
  groupadd "$linux_user"
fi
if ! id "$linux_user" >/dev/null 2>&1; then
  useradd --create-home --gid "$linux_user" --shell /bin/bash "$linux_user"
  printf '[CREATED] Linux user %s.\n' "$linux_user"
else
  usermod --home "/home/$linux_user" --gid "$linux_user" --shell /bin/bash "$linux_user"
  printf '[OK] Linux user %s already exists.\n' "$linux_user"
fi
install --directory --owner "$linux_user" --group "$linux_user" --mode 0755 "/home/$linux_user"

wsl_config='/etc/wsl.conf'
temporary_wsl_config="$(mktemp)"
trap 'rm -f "$temporary_wsl_config"' EXIT
if [[ -f $wsl_config ]]; then
  awk -v user="$linux_user" '
    BEGIN { in_user = 0; user_seen = 0; default_written = 0 }
    /^\[[^]]+\][[:space:]]*$/ {
      if (in_user && !default_written) { print "default=" user; default_written = 1 }
      in_user = ($0 ~ /^\[user\][[:space:]]*$/)
      if (in_user) { user_seen = 1 }
      print
      next
    }
    in_user && /^[[:space:]]*default[[:space:]]*=/ {
      if (!default_written) { print "default=" user; default_written = 1 }
      next
    }
    { print }
    END {
      if (in_user && !default_written) { print "default=" user }
      if (!user_seen) { print ""; print "[user]"; print "default=" user }
    }
  ' "$wsl_config" >"$temporary_wsl_config"
else
  printf '[user]\ndefault=%s\n' "$linux_user" >"$temporary_wsl_config"
fi
install --owner root --group root --mode 0644 "$temporary_wsl_config" "$wsl_config"

if ((${#packages[@]} > 0)); then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install --yes --no-install-recommends "${packages[@]}"
fi

install --directory --owner "$linux_user" --group "$linux_user" --mode 0755 "$project_root"

state_directory="/var/lib/pc-setup/$profile_name"
install --directory --mode 0755 "$state_directory"
temporary_manifest="$(mktemp)"
trap 'rm -f "$temporary_wsl_config" "$temporary_manifest"' EXIT
{
  printf 'schema=1\n'
  printf 'profile=%s\n' "$profile_name"
  printf 'linux_user=%s\n' "$linux_user"
  printf 'project_root=%s\n' "$project_root"
  for package in "${packages[@]}"; do
    version="$(dpkg-query --show --showformat='${Version}' "$package")"
    printf 'package=%s\t%s\n' "$package" "$version"
  done
} >"$temporary_manifest"
install --owner root --group root --mode 0644 "$temporary_manifest" "$state_directory/installed.tsv"

printf '[OK] WSL profile %s configured. State: %s\n' "$profile_name" "$state_directory/installed.tsv"
