#!/usr/bin/env bash
set -euo pipefail

profile_name=''
linux_user=''
project_root=''
packages=()

usage() {
  printf 'Usage: verify.sh --profile-name NAME --linux-user USER --project-root PATH [--package NAME ...]\n'
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

failures=0
check() {
  local name="$1"
  local result="$2"
  local detail="$3"
  if [[ $result == 1 ]]; then
    printf '[PASS] %s: %s\n' "$name" "$detail"
  else
    printf '[FAIL] %s: %s\n' "$name" "$detail"
    failures=$((failures + 1))
  fi
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
if [[ -d $project_root ]]; then
  owner="$(stat --format='%U' "$project_root")"
  group="$(stat --format='%G' "$project_root")"
  mode="$(stat --format='%a' "$project_root")"
  if [[ $owner == "$linux_user" && $group == "$linux_user" && $mode == 755 ]]; then
    check 'Project root' 1 "$project_root owner=$owner:$group mode=$mode"
  else
    check 'Project root' 0 "$project_root owner=$owner:$group mode=$mode"
  fi
else
  check 'Project root' 0 "$project_root missing"
fi

manifest="/var/lib/pc-setup/$profile_name/installed.tsv"
if [[ -f $manifest ]]; then
  manifest_owner="$(stat --format='%U:%G' "$manifest")"
  manifest_mode="$(stat --format='%a' "$manifest")"
  metadata_ok=1
  grep --fixed-strings --line-regexp 'schema=1' "$manifest" >/dev/null || metadata_ok=0
  grep --fixed-strings --line-regexp "profile=$profile_name" "$manifest" >/dev/null || metadata_ok=0
  grep --fixed-strings --line-regexp "linux_user=$linux_user" "$manifest" >/dev/null || metadata_ok=0
  grep --fixed-strings --line-regexp "project_root=$project_root" "$manifest" >/dev/null || metadata_ok=0
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
    if [[ -f $manifest ]]; then
      recorded_version="$(awk -F '\t' -v prefix="package=$package" '$1 == prefix { print $2 }' "$manifest")"
    fi
    if [[ $recorded_version == "$version" ]]; then
      check "Package $package" 1 "$version"
    else
      check "Package $package" 0 "installed=$version recorded=${recorded_version:-missing}"
    fi
  else
    check "Package $package" 0 'not installed'
  fi
done

if ((failures > 0)); then
  printf 'Result: FAIL (%d)\n' "$failures"
  exit 1
fi
printf 'Result: PASS\n'
