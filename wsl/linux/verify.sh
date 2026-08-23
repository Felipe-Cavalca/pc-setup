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
harness_command=''
harness_package=''
harness_version=''

usage() {
  printf 'Usage: verify.sh --profile-name NAME --linux-user USER --project-root PATH [options]\n'
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
    --harness-command) harness_command="${2:-}"; shift 2 ;;
    --harness-package) harness_package="${2:-}"; shift 2 ;;
    --harness-version) harness_version="${2:-}"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ! $profile_name =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]] ||
   [[ ! $linux_user =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] ||
   [[ ! $project_root_mode =~ ^[0-7]{3,4}$ ]]; then
  printf 'Invalid profile arguments.\n' >&2
  exit 2
fi
if [[ $project_root != "/home/$linux_user/"* ]] || [[ $project_root == *'/../'* ]] || [[ $project_root == *'/..' ]]; then
  printf 'Project root must stay below /home/%s/.\n' "$linux_user" >&2
  exit 2
fi
if [[ $set_default_user != true && $set_default_user != false ]] ||
   [[ $require_no_sudo != true && $require_no_sudo != false ]]; then
  printf 'Invalid boolean profile arguments.\n' >&2
  exit 2
fi
for package in "${packages[@]}"; do
  if [[ ! $package =~ ^[a-z0-9][a-z0-9+.-]*$ ]]; then printf 'Invalid APT package: %s\n' "$package" >&2; exit 2; fi
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

failures=0
check() {
  local name="$1" result="$2" detail="$3"
  if [[ $result == 1 ]]; then printf '[PASS] %s: %s\n' "$name" "$detail"
  else printf '[FAIL] %s: %s\n' "$name" "$detail"; failures=$((failures + 1)); fi
}

if id "$linux_user" >/dev/null 2>&1; then
  user_record="$(getent passwd "$linux_user")"
  user_home="$(cut --delimiter=: --fields=6 <<<"$user_record")"
  user_shell="$(cut --delimiter=: --fields=7 <<<"$user_record")"
  primary_group="$(id --group --name "$linux_user")"
  if [[ $user_home == "/home/$linux_user" && $user_shell == /bin/bash && $primary_group == "$linux_user" ]]; then
    check 'Linux user' 1 "$linux_user; home=$user_home; shell=$user_shell; group=$primary_group"
  else
    check 'Linux user' 0 "$linux_user; home=$user_home; shell=$user_shell; group=$primary_group"
  fi
else
  check 'Linux user' 0 "$linux_user missing"
fi

if [[ $require_no_sudo == true ]] && id "$linux_user" >/dev/null 2>&1; then
  privileged_groups="$(id --groups --name "$linux_user" | tr ' ' '\n' | grep --extended-regexp '^(sudo|wheel|docker|lxd)$' || true)"
  sudoers_rule=''
  if [[ -r /etc/sudoers ]]; then sudoers_rule="$(grep --extended-regexp "^[[:space:]]*${linux_user}([[:space:]]|$)" /etc/sudoers || true)"; fi
  if [[ -d /etc/sudoers.d ]]; then
    sudoers_rule+="$(grep --recursive --extended-regexp "^[[:space:]]*${linux_user}([[:space:]]|$)" /etc/sudoers.d 2>/dev/null || true)"
  fi
  password_state="$(passwd --status "$linux_user" | awk '{print $2}')"
  if [[ -z $privileged_groups && -z $sudoers_rule && $password_state == L ]]; then
    check 'Agent privilege' 1 'no sudo/wheel/docker/lxd membership or direct sudoers rule; password locked'
  else
    check 'Agent privilege' 0 "groups=${privileged_groups:-none}; sudoers=${sudoers_rule:-none}; password=$password_state"
  fi
fi

expected_group="$linux_user"
if [[ -n $shared_group ]]; then expected_group="$shared_group"; fi
if [[ -d $project_root ]]; then
  owner="$(stat --format='%U' "$project_root")"
  group="$(stat --format='%G' "$project_root")"
  mode="$(stat --format='%a' "$project_root")"
  normalized_mode="${project_root_mode#0}"
  if [[ $owner == "$linux_user" && $group == "$expected_group" && $mode == "$normalized_mode" ]]; then
    check 'Project root' 1 "$project_root owner=$owner:$group mode=$mode"
  else
    check 'Project root' 0 "$project_root owner=$owner:$group mode=$mode"
  fi
else
  check 'Project root' 0 "$project_root missing"
fi

if [[ -n $shared_group ]]; then
  for member in "$linux_user" "${shared_users[@]}"; do
    if id "$member" >/dev/null 2>&1 && id --groups --name "$member" | tr ' ' '\n' | grep --fixed-strings --line-regexp "$shared_group" >/dev/null; then
      check "Shared group $member" 1 "$shared_group"
    else
      check "Shared group $member" 0 "$shared_group missing"
    fi
  done
fi

manifest="/var/lib/pc-setup/$profile_name/installed.tsv"
if [[ -f $manifest ]]; then
  manifest_owner="$(stat --format='%U:%G' "$manifest")"
  manifest_mode="$(stat --format='%a' "$manifest")"
  metadata_ok=1
  for expected in \
    'schema=2' \
    "profile=$profile_name" \
    "linux_user=$linux_user" \
    "project_root=$project_root" \
    "project_root_mode=$project_root_mode" \
    "set_default_user=$set_default_user" \
    "require_no_sudo=$require_no_sudo" \
    "shared_group=$shared_group"; do
    grep --fixed-strings --line-regexp "$expected" "$manifest" >/dev/null || metadata_ok=0
  done
  recorded_package_count="$(grep --count '^package=' "$manifest" || true)"
  if [[ $recorded_package_count -ne ${#packages[@]} ]]; then metadata_ok=0; fi
  if [[ $manifest_owner == root:root && $manifest_mode == 644 && $metadata_ok == 1 ]]; then
    check 'State manifest' 1 "$manifest owner=$manifest_owner mode=$manifest_mode"
  else
    check 'State manifest' 0 "$manifest owner=$manifest_owner mode=$manifest_mode metadata=$metadata_ok"
  fi
else
  check 'State manifest' 0 "$manifest missing"
fi

for package in "${packages[@]}"; do
  if version="$(dpkg-query --show --showformat='${Version}' "$package" 2>/dev/null)" && [[ -n $version ]]; then
    recorded_version=''
    if [[ -f $manifest ]]; then recorded_version="$(awk -F '\t' -v prefix="package=$package" '$1 == prefix { print $2 }' "$manifest")"; fi
    if [[ $recorded_version == "$version" ]]; then check "Package $package" 1 "$version"
    else check "Package $package" 0 "installed=$version recorded=${recorded_version:-missing}"; fi
  else
    check "Package $package" 0 'not installed'
  fi
done

if [[ -n $ai_jail_version ]]; then
  ai_jail_resolved_version=''
  ai_jail_resolved_sha256=''
  release_helper="$(dirname -- "${BASH_SOURCE[0]}")/github-release.sh"
  if [[ ! -r $release_helper ]]; then
    check 'ai-jail release helper' 0 "$release_helper missing"
  else
    # shellcheck source=wsl/linux/github-release.sh
    source "$release_helper"
    asset_name="ai-jail-linux-${ai_jail_architecture}.tar.gz"
    IFS=$'\t' read -r ai_jail_resolved_version _ ai_jail_resolved_sha256 < <(
      pcsetup_resolve_github_release_asset "$ai_jail_repository" "$ai_jail_version" "$asset_name" "$ai_jail_sha256" "$ai_jail_require_asset_digest"
    )
  fi
  binary="$(command -v ai-jail || true)"
  version_output="$(ai-jail --version 2>/dev/null || true)"
  binary_owner=''
  binary_mode=''
  binary_sha256=''
  if [[ -n $binary ]]; then
    binary_owner="$(stat --format='%U:%G' "$binary")"
    binary_mode="$(stat --format='%a' "$binary")"
    binary_sha256="$(sha256sum "$binary" | awk '{print $1}')"
  fi
  recorded_ai_jail_policy=''
  recorded_ai_jail_repository=''
  recorded_ai_jail_version=''
  recorded_ai_jail_archive_sha256=''
  recorded_ai_jail_binary_sha256=''
  if [[ -f $manifest ]]; then
    recorded_ai_jail_policy="$(awk -F '\t' '$1 == "ai_jail_policy" { print $2 }' "$manifest")"
    recorded_ai_jail_repository="$(awk -F '\t' '$1 == "ai_jail_repository" { print $2 }' "$manifest")"
    recorded_ai_jail_version="$(awk -F '\t' '$1 == "ai_jail_version" { print $2 }' "$manifest")"
    recorded_ai_jail_archive_sha256="$(awk -F '\t' '$1 == "ai_jail_archive_sha256" { print $2 }' "$manifest")"
    recorded_ai_jail_binary_sha256="$(awk -F '\t' '$1 == "ai_jail_binary_sha256" { print $2 }' "$manifest")"
  fi
  if [[ -n ${ai_jail_resolved_version:-} && $version_output =~ (^|[[:space:]])$ai_jail_resolved_version($|[[:space:]]) ]] &&
     [[ $binary_owner == root:root && $binary_mode == 755 ]] &&
     [[ $recorded_ai_jail_policy == "$ai_jail_version" && $recorded_ai_jail_repository == "$ai_jail_repository" ]] &&
     [[ $recorded_ai_jail_version == "$ai_jail_resolved_version" && $recorded_ai_jail_archive_sha256 == "$ai_jail_resolved_sha256" ]] &&
     [[ -n $binary_sha256 && $recorded_ai_jail_binary_sha256 == "$binary_sha256" ]] &&
     [[ $(uname --machine) == "$ai_jail_architecture" ]]; then
    check 'ai-jail' 1 "$version_output; policy=$ai_jail_version; sha256=$binary_sha256; owner=$binary_owner mode=$binary_mode"
  else
    check 'ai-jail' 0 "policy=$ai_jail_version; latest=${ai_jail_resolved_version:-unresolved}; installed=${version_output:-missing}; binary=${binary:-missing}; owner=${binary_owner:-missing}; mode=${binary_mode:-missing}"
  fi
fi

if [[ -n $harness_command ]]; then
  npm_prefix="/home/$linux_user/.local"
  harness_launcher="/usr/local/bin/$harness_command"
  harness_binary="$npm_prefix/bin/$harness_command"
  launcher_target=''
  if [[ -L $harness_launcher ]]; then launcher_target="$(readlink --canonicalize-missing -- "$harness_launcher")"; fi
  actual_version="$(runuser --user "$linux_user" -- env HOME="/home/$linux_user" npm list --global --prefix "$npm_prefix" --depth 0 --json "$harness_package" 2>/dev/null | jq --raw-output --arg package "$harness_package" '.dependencies[$package].version // empty')"
  recorded_command=''
  recorded_package=''
  recorded_policy=''
  recorded_version=''
  if [[ -f $manifest ]]; then
    recorded_command="$(awk -F '\t' '$1 == "harness_command" { print $2 }' "$manifest")"
    recorded_package="$(awk -F '\t' '$1 == "harness_package" { print $2 }' "$manifest")"
    recorded_policy="$(awk -F '\t' '$1 == "harness_policy" { print $2 }' "$manifest")"
    recorded_version="$(awk -F '\t' '$1 == "harness_version" { print $2 }' "$manifest")"
  fi
  fixed_version_ok=1
  if [[ $harness_version != latest && $actual_version != "$harness_version" ]]; then fixed_version_ok=0; fi
  if [[ -x $harness_binary && $launcher_target == "$harness_binary" && $actual_version == "$recorded_version" &&
        $recorded_command == "$harness_command" && $recorded_package == "$harness_package" &&
        $recorded_policy == "$harness_version" && $fixed_version_ok == 1 ]] &&
     runuser --user "$linux_user" -- env HOME="/home/$linux_user" "$harness_launcher" --version >/dev/null 2>&1; then
    check 'Agent harness' 1 "$harness_package $actual_version; command=$harness_command"
  else
    check 'Agent harness' 0 "package=$harness_package; installed=${actual_version:-missing}; recorded=${recorded_version:-missing}; command=$harness_command"
  fi
fi

if ((failures > 0)); then printf 'Result: FAIL (%d)\n' "$failures"; exit 1; fi
printf 'Result: PASS\n'
