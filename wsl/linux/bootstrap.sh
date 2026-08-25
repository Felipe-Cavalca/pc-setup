#!/usr/bin/env bash
set -euo pipefail

profile_name=''
linux_user=''
project_root=''
project_root_mode='0755'
set_default_user='true'
require_no_sudo='false'
shared_group=''
shared_users=()
packages=()
ai_jail_version=''
ai_jail_repository=''
ai_jail_architecture=''
ai_jail_sha256=''
ai_jail_require_asset_digest='true'
ai_memory_version=''
ai_memory_repository=''
ai_memory_architecture=''
ai_memory_sha256=''
ai_memory_require_asset_digest='true'
ai_memory_client=''
ai_memory_project_strategy=''
ai_memory_server_url=''
harness_command=''
harness_package=''
harness_version=''
temporary_paths=()

cleanup() {
  local path
  for path in "${temporary_paths[@]}"; do rm -rf -- "$path"; done
}
trap cleanup EXIT

usage() {
  printf 'Usage: bootstrap.sh --profile-name NAME --linux-user USER --project-root PATH [options]\n'
}

while (($# > 0)); do
  case "$1" in
    --profile-name) profile_name="${2:-}"; shift 2 ;;
    --linux-user) linux_user="${2:-}"; shift 2 ;;
    --project-root) project_root="${2:-}"; shift 2 ;;
    --project-root-mode) project_root_mode="${2:-}"; shift 2 ;;
    --set-default-user) set_default_user="${2:-}"; shift 2 ;;
    --require-no-sudo) require_no_sudo="${2:-}"; shift 2 ;;
    --shared-group) shared_group="${2:-}"; shift 2 ;;
    --shared-with) shared_users+=("${2:-}"); shift 2 ;;
    --package) packages+=("${2:-}"); shift 2 ;;
    --ai-jail-repository) ai_jail_repository="${2:-}"; shift 2 ;;
    --ai-jail-version) ai_jail_version="${2:-}"; shift 2 ;;
    --ai-jail-architecture) ai_jail_architecture="${2:-}"; shift 2 ;;
    --ai-jail-sha256) ai_jail_sha256="${2:-}"; shift 2 ;;
    --ai-jail-require-asset-digest) ai_jail_require_asset_digest="${2:-}"; shift 2 ;;
    --ai-memory-repository) ai_memory_repository="${2:-}"; shift 2 ;;
    --ai-memory-version) ai_memory_version="${2:-}"; shift 2 ;;
    --ai-memory-architecture) ai_memory_architecture="${2:-}"; shift 2 ;;
    --ai-memory-sha256) ai_memory_sha256="${2:-}"; shift 2 ;;
    --ai-memory-require-asset-digest) ai_memory_require_asset_digest="${2:-}"; shift 2 ;;
    --ai-memory-client) ai_memory_client="${2:-}"; shift 2 ;;
    --ai-memory-project-strategy) ai_memory_project_strategy="${2:-}"; shift 2 ;;
    --ai-memory-server-url) ai_memory_server_url="${2:-}"; shift 2 ;;
    --harness-command) harness_command="${2:-}"; shift 2 ;;
    --harness-package) harness_package="${2:-}"; shift 2 ;;
    --harness-version) harness_version="${2:-}"; shift 2 ;;
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
if [[ ! $project_root_mode =~ ^[0-7]{3,4}$ ]]; then
  printf 'Invalid project root mode.\n' >&2
  exit 2
fi
if [[ $set_default_user != true && $set_default_user != false ]]; then
  printf 'Invalid set-default-user value.\n' >&2
  exit 2
fi
if [[ $require_no_sudo != true && $require_no_sudo != false ]]; then
  printf 'Invalid require-no-sudo value.\n' >&2
  exit 2
fi
if [[ -n $shared_group && ! $shared_group =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  printf 'Invalid shared group.\n' >&2
  exit 2
fi
for shared_user in "${shared_users[@]}"; do
  if [[ ! $shared_user =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    printf 'Invalid shared user: %s\n' "$shared_user" >&2
    exit 2
  fi
done
for package in "${packages[@]}"; do
  if [[ ! $package =~ ^[a-z0-9][a-z0-9+.-]*$ ]]; then
    printf 'Invalid APT package: %s\n' "$package" >&2
    exit 2
  fi
done
if [[ -n $ai_jail_version ]]; then
  if [[ $ai_jail_version != latest && ! $ai_jail_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
     [[ ! $ai_jail_repository =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
     [[ ! $ai_jail_architecture =~ ^[a-z0-9_]+$ ]] ||
     [[ -n $ai_jail_sha256 && ! $ai_jail_sha256 =~ ^[a-fA-F0-9]{64}$ ]] ||
     [[ $ai_jail_require_asset_digest != true && $ai_jail_require_asset_digest != false ]]; then
    printf 'Invalid ai-jail release metadata.\n' >&2
    exit 2
  fi
  if [[ $ai_jail_version != latest && ! $ai_jail_sha256 =~ ^[a-fA-F0-9]{64}$ ]]; then
    printf 'An exact ai-jail release requires a configured SHA-256.\n' >&2
    exit 2
  fi
fi
if [[ -n $ai_memory_version ]]; then
  if [[ $ai_memory_version != latest && ! $ai_memory_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
     [[ ! $ai_memory_repository =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] ||
     [[ ! $ai_memory_architecture =~ ^[a-z0-9_]+$ ]] ||
     [[ -n $ai_memory_sha256 && ! $ai_memory_sha256 =~ ^[a-fA-F0-9]{64}$ ]] ||
     [[ $ai_memory_require_asset_digest != true && $ai_memory_require_asset_digest != false ]] ||
     [[ ! $ai_memory_client =~ ^[a-z0-9][a-z0-9-]*$ ]] ||
     [[ $ai_memory_project_strategy != repo-root && $ai_memory_project_strategy != basename ]] ||
     [[ ! $ai_memory_server_url =~ ^http://127\.0\.0\.1:([1-9][0-9]{0,4})$ ]] ||
     ((10#${BASH_REMATCH[1]:-0} > 65535)); then
    printf 'Invalid ai-memory release or integration metadata.\n' >&2
    exit 2
  fi
  if [[ $ai_memory_version != latest && ! $ai_memory_sha256 =~ ^[a-fA-F0-9]{64}$ ]]; then
    printf 'An exact ai-memory release requires a configured SHA-256.\n' >&2
    exit 2
  fi
fi
if [[ -n $harness_command || -n $harness_package || -n $harness_version ]]; then
  if [[ ! $harness_command =~ ^[A-Za-z0-9._-]+$ ]] ||
     [[ ! $harness_package =~ ^@[a-z0-9._-]+/[a-z0-9._-]+$ ]]; then
    printf 'Invalid harness metadata.\n' >&2
    exit 2
  fi
  if [[ $harness_version != latest ]] && [[ ! $harness_version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
    printf 'Invalid harness metadata.\n' >&2
    exit 2
  fi
fi

resolved_project_root="$(readlink --canonicalize-missing -- "$project_root")"
if [[ $resolved_project_root != "$project_root" ]]; then
  printf 'Project root must not contain symlinks or non-canonical components: %s\n' "$project_root" >&2
  exit 2
fi

if ! getent group "$linux_user" >/dev/null 2>&1; then groupadd "$linux_user"; fi
if ! id "$linux_user" >/dev/null 2>&1; then
  useradd --create-home --gid "$linux_user" --shell /bin/bash "$linux_user"
  printf '[CREATED] Linux user %s.\n' "$linux_user"
else
  usermod --home "/home/$linux_user" --gid "$linux_user" --shell /bin/bash "$linux_user"
  printf '[OK] Linux user %s already exists.\n' "$linux_user"
fi
install --directory --owner "$linux_user" --group "$linux_user" --mode 0755 "/home/$linux_user"

if [[ $require_no_sudo == true ]]; then
  passwd --lock "$linux_user" >/dev/null
  for privileged_group in sudo wheel docker lxd; do
    if getent group "$privileged_group" >/dev/null 2>&1 && id --groups --name "$linux_user" | tr ' ' '\n' | grep --fixed-strings --line-regexp "$privileged_group" >/dev/null; then
      gpasswd --delete "$linux_user" "$privileged_group" >/dev/null
    fi
  done
  sudoers_rule=''
  if [[ -r /etc/sudoers ]]; then sudoers_rule="$(grep --extended-regexp "^[[:space:]]*${linux_user}([[:space:]]|$)" /etc/sudoers || true)"; fi
  if [[ -d /etc/sudoers.d ]]; then
    sudoers_rule+="$(grep --recursive --extended-regexp "^[[:space:]]*${linux_user}([[:space:]]|$)" /etc/sudoers.d 2>/dev/null || true)"
  fi
  if [[ -n $sudoers_rule ]]; then
    printf 'Refusing to keep an unmanaged sudoers rule for %s. Remove it manually and retry.\n' "$linux_user" >&2
    exit 1
  fi
fi

project_group="$linux_user"
if [[ -n $shared_group ]]; then
  if ! getent group "$shared_group" >/dev/null 2>&1; then groupadd "$shared_group"; fi
  usermod --append --groups "$shared_group" "$linux_user"
  for shared_user in "${shared_users[@]}"; do
    if ! id "$shared_user" >/dev/null 2>&1; then
      printf 'Shared user must exist before this profile is applied: %s\n' "$shared_user" >&2
      exit 1
    fi
    usermod --append --groups "$shared_group" "$shared_user"
  done
  project_group="$shared_group"
fi

if [[ $set_default_user == true ]]; then
  wsl_config='/etc/wsl.conf'
  temporary_wsl_config="$(mktemp)"
  temporary_paths+=("$temporary_wsl_config")
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
fi

if [[ -n $ai_memory_version ]]; then
  wsl_config='/etc/wsl.conf'
  temporary_wsl_systemd_config="$(mktemp)"
  temporary_paths+=("$temporary_wsl_systemd_config")
  if [[ -f $wsl_config ]]; then
    awk '
    BEGIN { in_boot = 0; boot_seen = 0; systemd_written = 0 }
    /^\[[^]]+\][[:space:]]*$/ {
      if (in_boot && !systemd_written) { print "systemd=true"; systemd_written = 1 }
      in_boot = ($0 ~ /^\[boot\][[:space:]]*$/)
      if (in_boot) { boot_seen = 1 }
      print
      next
    }
    in_boot && /^[[:space:]]*systemd[[:space:]]*=/ {
      if (!systemd_written) { print "systemd=true"; systemd_written = 1 }
      next
    }
    { print }
    END {
      if (in_boot && !systemd_written) { print "systemd=true" }
      if (!boot_seen) { print ""; print "[boot]"; print "systemd=true" }
    }
    ' "$wsl_config" >"$temporary_wsl_systemd_config"
  else
    printf '[boot]\nsystemd=true\n' >"$temporary_wsl_systemd_config"
  fi
  install --owner root --group root --mode 0644 "$temporary_wsl_systemd_config" "$wsl_config"
fi

if ((${#packages[@]} > 0)); then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install --yes --no-install-recommends "${packages[@]}"
fi

install --directory --owner "$linux_user" --group "$project_group" --mode "$project_root_mode" "$project_root"

state_directory="/var/lib/pc-setup/$profile_name"
install --directory --mode 0755 "$state_directory"

if [[ -n $ai_jail_version ]]; then
  ai_jail_resolved_version=''
  ai_jail_url=''
  ai_jail_resolved_sha256=''
  actual_architecture="$(uname --machine)"
  if [[ $actual_architecture != "$ai_jail_architecture" ]]; then
    printf 'ai-jail architecture mismatch: configured=%s actual=%s\n' "$ai_jail_architecture" "$actual_architecture" >&2
    exit 1
  fi
  release_helper="$(dirname -- "${BASH_SOURCE[0]}")/github-release.sh"
  if [[ ! -r $release_helper ]]; then
    printf 'GitHub release helper is missing: %s\n' "$release_helper" >&2
    exit 1
  fi
  # shellcheck source=wsl/linux/github-release.sh
  source "$release_helper"
  asset_name="ai-jail-linux-${ai_jail_architecture}.tar.gz"
  IFS=$'\t' read -r ai_jail_resolved_version ai_jail_url ai_jail_resolved_sha256 < <(
    pcsetup_resolve_github_release_asset "$ai_jail_repository" "$ai_jail_version" "$asset_name" "$ai_jail_sha256" "$ai_jail_require_asset_digest"
  )
  if [[ -z $ai_jail_resolved_version || -z $ai_jail_url || -z $ai_jail_resolved_sha256 ]]; then
    printf 'Could not resolve trusted ai-jail release metadata.\n' >&2
    exit 1
  fi

  previous_manifest="$state_directory/installed.tsv"
  installed_binary_sha256=''
  if [[ -x /usr/local/bin/ai-jail ]]; then installed_binary_sha256="$(sha256sum /usr/local/bin/ai-jail | awk '{print $1}')"; fi
  recorded_ai_jail_binary_sha256=''
  recorded_ai_jail_archive_sha256=''
  if [[ -f $previous_manifest ]]; then
    recorded_ai_jail_binary_sha256="$(awk -F '\t' '$1 == "ai_jail_binary_sha256" { print $2 }' "$previous_manifest")"
    recorded_ai_jail_archive_sha256="$(awk -F '\t' '$1 == "ai_jail_archive_sha256" { print $2 }' "$previous_manifest")"
  fi
  ai_jail_needs_install=true
  if command -v ai-jail >/dev/null 2>&1 &&
     ai-jail --version 2>/dev/null | grep --extended-regexp "(^| )${ai_jail_resolved_version}($| )" >/dev/null &&
     [[ $recorded_ai_jail_archive_sha256 == "$ai_jail_resolved_sha256" ]] &&
     [[ -n $recorded_ai_jail_binary_sha256 && $installed_binary_sha256 == "$recorded_ai_jail_binary_sha256" ]]; then
    ai_jail_needs_install=false
  fi
  if [[ $ai_jail_needs_install == true ]]; then
    temporary_ai_jail="$(mktemp --directory)"
    temporary_paths+=("$temporary_ai_jail")
    archive="$temporary_ai_jail/ai-jail.tar.gz"
    curl --fail --location --silent --show-error "$ai_jail_url" --output "$archive"
    printf '%s  %s\n' "$ai_jail_resolved_sha256" "$archive" | sha256sum --check --status
    if tar --list --gzip --file "$archive" | grep --extended-regexp '(^/|(^|/)\.\.(/|$))' >/dev/null; then
      printf 'The ai-jail archive contains an unsafe path.\n' >&2
      exit 1
    fi
    if tar --list --verbose --gzip --file "$archive" | awk '$1 !~ /^[-d]/ { unsafe = 1 } END { exit unsafe ? 0 : 1 }'; then
      printf 'The ai-jail archive contains a link or unsupported entry type.\n' >&2
      exit 1
    fi
    tar --extract --gzip --no-same-owner --no-same-permissions --file "$archive" --directory "$temporary_ai_jail"
    binary="$(find "$temporary_ai_jail" -maxdepth 2 -type f -name ai-jail -print -quit)"
    if [[ -z $binary ]]; then
      printf 'ai-jail binary missing from pinned archive.\n' >&2
      exit 1
    fi
    install --owner root --group root --mode 0755 "$binary" /usr/local/bin/ai-jail
  fi
  if ! ai-jail --version 2>/dev/null | grep --extended-regexp "(^| )${ai_jail_resolved_version}($| )" >/dev/null; then
    printf 'Installed ai-jail version does not match %s.\n' "$ai_jail_resolved_version" >&2
    exit 1
  fi
  ai_jail_binary_sha256="$(sha256sum /usr/local/bin/ai-jail | awk '{print $1}')"
fi

if [[ -n $ai_memory_version ]]; then
  ai_memory_resolved_version=''
  ai_memory_url=''
  ai_memory_resolved_sha256=''
  actual_architecture="$(uname --machine)"
  if [[ $actual_architecture != "$ai_memory_architecture" ]]; then
    printf 'ai-memory architecture mismatch: configured=%s actual=%s\n' "$ai_memory_architecture" "$actual_architecture" >&2
    exit 1
  fi
  release_helper="$(dirname -- "${BASH_SOURCE[0]}")/github-release.sh"
  if [[ ! -r $release_helper ]]; then
    printf 'GitHub release helper is missing: %s\n' "$release_helper" >&2
    exit 1
  fi
  # shellcheck source=wsl/linux/github-release.sh
  source "$release_helper"
  asset_name="ai-memory-linux-${ai_memory_architecture}.tar.gz"
  IFS=$'\t' read -r ai_memory_resolved_version ai_memory_url ai_memory_resolved_sha256 < <(
    pcsetup_resolve_github_release_asset "$ai_memory_repository" "$ai_memory_version" "$asset_name" "$ai_memory_sha256" "$ai_memory_require_asset_digest"
  )
  if [[ -z $ai_memory_resolved_version || -z $ai_memory_url || -z $ai_memory_resolved_sha256 ]]; then
    printf 'Could not resolve trusted ai-memory release metadata.\n' >&2
    exit 1
  fi

  previous_manifest="$state_directory/installed.tsv"
  ai_memory_install_directory="/opt/pc-setup/ai-memory/$ai_memory_resolved_version"
  ai_memory_managed_binary="$ai_memory_install_directory/ai-memory"
  installed_binary_sha256=''
  if [[ -x /usr/local/bin/ai-memory ]]; then installed_binary_sha256="$(sha256sum /usr/local/bin/ai-memory | awk '{print $1}')"; fi
  recorded_ai_memory_binary_sha256=''
  recorded_ai_memory_archive_sha256=''
  if [[ -f $previous_manifest ]]; then
    recorded_ai_memory_binary_sha256="$(awk -F '\t' '$1 == "ai_memory_binary_sha256" { print $2 }' "$previous_manifest")"
    recorded_ai_memory_archive_sha256="$(awk -F '\t' '$1 == "ai_memory_archive_sha256" { print $2 }' "$previous_manifest")"
  fi
  ai_memory_needs_install=true
  if [[ -x $ai_memory_managed_binary ]] &&
     /usr/local/bin/ai-memory --version 2>/dev/null | grep --extended-regexp "(^| )${ai_memory_resolved_version}($| )" >/dev/null &&
     [[ $recorded_ai_memory_archive_sha256 == "$ai_memory_resolved_sha256" ]] &&
     [[ -n $recorded_ai_memory_binary_sha256 && $installed_binary_sha256 == "$recorded_ai_memory_binary_sha256" ]]; then
    ai_memory_needs_install=false
  fi
  if [[ $ai_memory_needs_install == true ]]; then
    temporary_ai_memory="$(mktemp --directory)"
    temporary_paths+=("$temporary_ai_memory")
    archive="$temporary_ai_memory/ai-memory.tar.gz"
    curl --fail --location --silent --show-error "$ai_memory_url" --output "$archive"
    printf '%s  %s\n' "$ai_memory_resolved_sha256" "$archive" | sha256sum --check --status
    if tar --list --gzip --file "$archive" | grep --extended-regexp '(^/|(^|/)\.\.(/|$))' >/dev/null; then
      printf 'The ai-memory archive contains an unsafe path.\n' >&2
      exit 1
    fi
    if tar --list --verbose --gzip --file "$archive" | awk '$1 !~ /^[-d]/ { unsafe = 1 } END { exit unsafe ? 0 : 1 }'; then
      printf 'The ai-memory archive contains a link or unsupported entry type.\n' >&2
      exit 1
    fi
    tar --extract --gzip --no-same-owner --no-same-permissions --file "$archive" --directory "$temporary_ai_memory"
    binary="$(find "$temporary_ai_memory" -maxdepth 3 -type f -name ai-memory -print -quit)"
    if [[ -z $binary ]]; then
      printf 'ai-memory binary missing from release archive.\n' >&2
      exit 1
    fi
    release_root="$(dirname -- "$binary")"
    install --directory --owner root --group root --mode 0755 "$ai_memory_install_directory"
    cp --archive --no-preserve=ownership "$release_root/." "$ai_memory_install_directory/"
    chown --recursive root:root "$ai_memory_install_directory"
    chmod 0755 "$ai_memory_managed_binary"
  fi
  ai_memory_launcher='/usr/local/bin/ai-memory'
  if [[ -e $ai_memory_launcher && ! -L $ai_memory_launcher ]]; then
    printf 'Refusing to replace unmanaged ai-memory command: %s\n' "$ai_memory_launcher" >&2
    exit 1
  fi
  if [[ -L $ai_memory_launcher ]]; then
    existing_target="$(readlink --canonicalize-missing -- "$ai_memory_launcher")"
    if [[ $existing_target != /opt/pc-setup/ai-memory/* ]]; then
      printf 'Refusing to replace ai-memory symlink outside the managed prefix: %s -> %s\n' "$ai_memory_launcher" "$existing_target" >&2
      exit 1
    fi
  fi
  ln --symbolic --force "$ai_memory_managed_binary" "$ai_memory_launcher"
  if ! ai-memory --version 2>/dev/null | grep --extended-regexp "(^| )${ai_memory_resolved_version}($| )" >/dev/null; then
    printf 'Installed ai-memory version does not match %s.\n' "$ai_memory_resolved_version" >&2
    exit 1
  fi
  ai_memory_binary_sha256="$(sha256sum "$ai_memory_managed_binary" | awk '{print $1}')"
fi

if [[ -n $harness_command ]]; then
  npm_prefix="/home/$linux_user/.local"
  install --directory --owner "$linux_user" --group "$linux_user" --mode 0755 "$npm_prefix"

  previous_manifest="$state_directory/installed.tsv"
  if [[ -f $previous_manifest ]]; then
    previous_package="$(awk -F '\t' '$1 == "harness_package" { print $2 }' "$previous_manifest")"
    previous_command="$(awk -F '\t' '$1 == "harness_command" { print $2 }' "$previous_manifest")"
    if [[ -n $previous_package && $previous_package != "$harness_package" ]]; then
      runuser --user "$linux_user" -- env HOME="/home/$linux_user" npm uninstall --global --prefix "$npm_prefix" "$previous_package" --no-audit --no-fund
    fi
    if [[ -n $previous_command && $previous_command != "$harness_command" && -L "/usr/local/bin/$previous_command" ]]; then
      previous_target="$(readlink --canonicalize-missing -- "/usr/local/bin/$previous_command")"
      if [[ $previous_target == "$npm_prefix/"* ]]; then rm -- "/usr/local/bin/$previous_command"; fi
    fi
  fi

  runuser --user "$linux_user" -- env HOME="/home/$linux_user" npm install --global --prefix "$npm_prefix" "${harness_package}@${harness_version}" --no-audit --no-fund
  harness_binary="$npm_prefix/bin/$harness_command"
  if [[ ! -x $harness_binary ]]; then
    printf 'Harness command missing after NPM install: %s\n' "$harness_binary" >&2
    exit 1
  fi
  harness_launcher="/usr/local/bin/$harness_command"
  if [[ -e $harness_launcher && ! -L $harness_launcher ]]; then
    printf 'Refusing to replace unmanaged harness command: %s\n' "$harness_launcher" >&2
    exit 1
  fi
  if [[ -L $harness_launcher ]]; then
    existing_target="$(readlink --canonicalize-missing -- "$harness_launcher")"
    if [[ $existing_target != "$npm_prefix/"* ]]; then
      printf 'Refusing to replace harness symlink outside the managed prefix: %s -> %s\n' "$harness_launcher" "$existing_target" >&2
      exit 1
    fi
  fi
  ln --symbolic --force "$harness_binary" "$harness_launcher"
  harness_actual_version="$(runuser --user "$linux_user" -- env HOME="/home/$linux_user" npm list --global --prefix "$npm_prefix" --depth 0 --json "$harness_package" | jq --exit-status --raw-output --arg package "$harness_package" '.dependencies[$package].version')"
  if [[ $harness_version != latest && $harness_actual_version != "$harness_version" ]]; then
    printf 'Harness version mismatch: configured=%s installed=%s\n' "$harness_version" "$harness_actual_version" >&2
    exit 1
  fi
  harness_command_output=''
  if ! harness_command_output="$(runuser --user "$linux_user" -- env HOME="/home/$linux_user" "$harness_launcher" --version 2>&1)"; then
    harness_command_output="${harness_command_output//$'\n'/ }"
    printf 'Harness command failed after install: %s; output=%s\n' "$harness_command" "${harness_command_output:-missing}" >&2
    exit 1
  fi
fi

if [[ -n $ai_memory_version ]]; then
  ai_memory_home="/home/$linux_user"
  ai_memory_data_directory="$ai_memory_home/.local/share/ai-memory"
  ai_memory_config_directory="$ai_memory_home/.config/ai-memory"
  ai_memory_config="$ai_memory_config_directory/config.toml"
  ai_memory_env="$ai_memory_config_directory/env"
  install --directory --owner "$linux_user" --group "$linux_user" --mode 0700 "$ai_memory_data_directory" "$ai_memory_config_directory"

  if [[ ! -f $ai_memory_config ]]; then
    runuser --user "$linux_user" -- env HOME="$ai_memory_home" \
      /usr/local/bin/ai-memory --data-dir "$ai_memory_data_directory" --config "$ai_memory_config" init
  fi
  if [[ ! -f $ai_memory_env ]] || ! grep --quiet '^AI_MEMORY_AUTH_TOKEN=' "$ai_memory_env"; then
    ai_memory_auth_token="$(runuser --user "$linux_user" -- env HOME="$ai_memory_home" /usr/local/bin/ai-memory generate-auth-token)"
    if [[ ! $ai_memory_auth_token =~ ^[A-Za-z0-9._~-]{32,}$ ]]; then
      printf 'ai-memory generated an invalid authentication token.\n' >&2
      exit 1
    fi
    printf 'AI_MEMORY_AUTH_TOKEN=%s\n' "$ai_memory_auth_token" >>"$ai_memory_env"
  fi
  ai_memory_auth_token="$(awk -F= '$1 == "AI_MEMORY_AUTH_TOKEN" { print substr($0, index($0, "=") + 1) }' "$ai_memory_env" | tail --lines=1)"
  if [[ ! $ai_memory_auth_token =~ ^[A-Za-z0-9._~-]{32,}$ ]]; then
    printf 'ai-memory authentication token is missing or invalid.\n' >&2
    exit 1
  fi
  chown "$linux_user:$linux_user" "$ai_memory_config" "$ai_memory_env"
  chmod 0600 "$ai_memory_config" "$ai_memory_env"

  runuser --user "$linux_user" -- env \
    HOME="$ai_memory_home" \
    AI_MEMORY_SERVER_URL="$ai_memory_server_url" \
    AI_MEMORY_AUTH_TOKEN="$ai_memory_auth_token" \
    /usr/local/bin/ai-memory install-mcp --client "$ai_memory_client" --apply
  runuser --user "$linux_user" -- env \
    HOME="$ai_memory_home" \
    AI_MEMORY_SERVER_URL="$ai_memory_server_url" \
    AI_MEMORY_AUTH_TOKEN="$ai_memory_auth_token" \
    /usr/local/bin/ai-memory install-hooks --agent "$ai_memory_client" --project-strategy "$ai_memory_project_strategy" --apply

  if [[ $ai_memory_client == codex ]]; then
    codex_config_directory="$ai_memory_home/.codex"
    codex_config="$codex_config_directory/config.toml"
    install --directory --owner "$linux_user" --group "$linux_user" --mode 0700 "$codex_config_directory"
    if [[ ! -f $codex_config ]]; then
      printf 'ai-memory did not create the expected Codex MCP configuration: %s\n' "$codex_config" >&2
      exit 1
    fi
    chown "$linux_user:$linux_user" "$codex_config"
    chmod 0600 "$codex_config"
  fi

  ai_memory_service="pc-setup-ai-memory-${profile_name,,}.service"
  ai_memory_service_path="/etc/systemd/system/$ai_memory_service"
  ai_memory_bind="${ai_memory_server_url#http://}"
  temporary_service="$(mktemp)"
  temporary_paths+=("$temporary_service")
  cat >"$temporary_service" <<EOF
[Unit]
Description=pc-setup ai-memory ($profile_name)
After=network-online.target

[Service]
Type=simple
User=$linux_user
Group=$linux_user
Environment=HOME=$ai_memory_home
EnvironmentFile=$ai_memory_env
ExecStart=/usr/local/bin/ai-memory --data-dir $ai_memory_data_directory --config $ai_memory_config serve --transport http --bind $ai_memory_bind
Restart=on-failure
RestartSec=2
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=$ai_memory_data_directory

[Install]
WantedBy=multi-user.target
EOF
  install --owner root --group root --mode 0644 "$temporary_service" "$ai_memory_service_path"
  systemctl enable --no-reload "$ai_memory_service" >/dev/null
  if [[ $(</proc/1/comm) == systemd ]]; then
    systemctl daemon-reload
    systemctl restart "$ai_memory_service"
  fi
fi

temporary_manifest="$(mktemp)"
temporary_paths+=("$temporary_manifest")
{
  printf 'schema=2\n'
  printf 'profile=%s\n' "$profile_name"
  printf 'linux_user=%s\n' "$linux_user"
  printf 'project_root=%s\n' "$project_root"
  printf 'project_root_mode=%s\n' "$project_root_mode"
  printf 'set_default_user=%s\n' "$set_default_user"
  printf 'require_no_sudo=%s\n' "$require_no_sudo"
  printf 'shared_group=%s\n' "$shared_group"
  for shared_user in "${shared_users[@]}"; do printf 'shared_with=%s\n' "$shared_user"; done
  for package in "${packages[@]}"; do
    version="$(dpkg-query --show --showformat='${Version}' "$package")"
    printf 'package=%s\t%s\n' "$package" "$version"
  done
  if [[ -n $ai_jail_version ]]; then
    printf 'ai_jail_policy\t%s\n' "$ai_jail_version"
    printf 'ai_jail_repository\t%s\n' "$ai_jail_repository"
    printf 'ai_jail_version\t%s\n' "$ai_jail_resolved_version"
    printf 'ai_jail_archive_sha256\t%s\n' "$ai_jail_resolved_sha256"
    printf 'ai_jail_binary_sha256\t%s\n' "$ai_jail_binary_sha256"
  fi
  if [[ -n $ai_memory_version ]]; then
    printf 'ai_memory_policy\t%s\n' "$ai_memory_version"
    printf 'ai_memory_repository\t%s\n' "$ai_memory_repository"
    printf 'ai_memory_version\t%s\n' "$ai_memory_resolved_version"
    printf 'ai_memory_archive_sha256\t%s\n' "$ai_memory_resolved_sha256"
    printf 'ai_memory_binary_sha256\t%s\n' "$ai_memory_binary_sha256"
    printf 'ai_memory_client\t%s\n' "$ai_memory_client"
    printf 'ai_memory_project_strategy\t%s\n' "$ai_memory_project_strategy"
    printf 'ai_memory_server_url\t%s\n' "$ai_memory_server_url"
    printf 'ai_memory_service\t%s\n' "$ai_memory_service"
  fi
  if [[ -n $harness_command ]]; then
    printf 'harness_command\t%s\n' "$harness_command"
    printf 'harness_package\t%s\n' "$harness_package"
    printf 'harness_policy\t%s\n' "$harness_version"
    printf 'harness_version\t%s\n' "$harness_actual_version"
  fi
} >"$temporary_manifest"
install --owner root --group root --mode 0644 "$temporary_manifest" "$state_directory/installed.tsv"

printf '[OK] WSL profile %s configured. State: %s\n' "$profile_name" "$state_directory/installed.tsv"
