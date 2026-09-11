#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
launcher="$root_dir/scripts/Start-Agent.ps1"

match_script="$(awk '
    /^[[:space:]]*\$matchScript = @\047$/ { capture=1; next }
    capture && /^[[:space:]]*\047@$/ { exit }
    capture { print }
' "$launcher")"

if [[ -z "$match_script" ]] || ! grep -Fq "compgen -G \"\$pattern\"" <<<"$match_script"; then
    echo 'FAIL: nao foi possivel extrair o matcher real do preflight.' >&2
    exit 1
fi

if ! grep -Fq "bash -c \$matchScript 'pc-setup' \$ProjectPath @Patterns" "$launcher"; then
    echo 'FAIL: o launcher deve reservar um argv[0] literal para bash -c ao atravessar wsl.exe.' >&2
    exit 1
fi

if grep -Fq 'bash -c $matchScript -- $ProjectPath @Patterns' "$launcher"; then
    echo 'FAIL: -- nao pode ser usado como argv[0] de bash -c atraves do wsl.exe.' >&2
    exit 1
fi

temp_root="$(mktemp -d)"
cleanup() {
    chmod -R u+rwx "$temp_root" 2>/dev/null || true
    rm -rf -- "$temp_root"
}
trap cleanup EXIT

project="$temp_root/proj[1] literal"
sibling="$temp_root/proj1 literal"
mkdir -p -- "$project/secrets/sub" "$project/blocked" "$sibling"
touch -- \
    "$project/.env" \
    "$project/.env.production.local" \
    "$project/credentials.json" \
    "$project/secrets/sub/token" \
    "$sibling/.env"
chmod 000 "$project/blocked"

patterns=(.env .env.local '.env.*.local' credentials.json 'secrets/**')
output="$(bash -c "$match_script" pc-setup "$project" "${patterns[@]}")"

[[ "$output" == *"$project/.env"* ]]
[[ "$output" == *"$project/.env.production.local"* ]]
[[ "$output" == *"$project/credentials.json"* ]]
[[ "$output" == *"$project/secrets/"* ]]
[[ "$output" != *"$sibling/.env"* ]]

clean_project="$temp_root/clean[1] literal"
mkdir -p -- "$clean_project/blocked"
chmod 000 "$clean_project/blocked"
clean_output="$(bash -c "$match_script" pc-setup "$clean_project" "${patterns[@]}")"
[[ -z "$clean_output" ]]

unreadable_sensitive="$temp_root/unreadable-sensitive"
mkdir -p -- "$unreadable_sensitive/secrets"
chmod 000 "$unreadable_sensitive/secrets"
set +e
bash -c "$match_script" pc-setup "$unreadable_sensitive" "${patterns[@]}" >/dev/null 2>&1
unreadable_sensitive_exit=$?
set -e
[[ $unreadable_sensitive_exit -eq 3 ]]

set +e
bash -c "$match_script" pc-setup "$temp_root/nao-existe" "${patterns[@]}" >/dev/null 2>&1
missing_root_exit=$?
set -e
[[ $missing_root_exit -eq 2 ]]

echo 'PASS: matcher real preserva argv no WSL, detecta segredos, trata raiz literal e falhas de acesso.'
