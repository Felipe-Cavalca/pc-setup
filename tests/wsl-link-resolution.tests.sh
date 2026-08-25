#!/usr/bin/env bash
set -euo pipefail

temporary_directory="$(mktemp --directory)"
cleanup() {
  rm --recursive --force -- "$temporary_directory"
}
trap cleanup EXIT

npm_prefix="$temporary_directory/home/agent/.local"
package_binary="$npm_prefix/lib/node_modules/@openai/codex/bin/codex.js"
harness_binary="$npm_prefix/bin/codex"
harness_launcher="$temporary_directory/usr/local/bin/codex"

mkdir --parents -- "$(dirname -- "$package_binary")" "$(dirname -- "$harness_binary")" "$(dirname -- "$harness_launcher")"
printf '#!/usr/bin/env bash\nprintf "codex-cli 0.149.1\\n"\n' >"$package_binary"
chmod 0755 "$package_binary"
ln --symbolic ../lib/node_modules/@openai/codex/bin/codex.js "$harness_binary"
ln --symbolic "$harness_binary" "$harness_launcher"

launcher_target="$(readlink --canonicalize-missing -- "$harness_launcher")"
harness_binary_target="$(readlink --canonicalize-missing -- "$harness_binary")"

if [[ $launcher_target != "$harness_binary_target" ]]; then
  printf '[FAIL] Os dois links nao resolveram para o mesmo executavel. launcher=%s expected=%s\n' "$launcher_target" "$harness_binary_target" >&2
  exit 1
fi
if [[ $launcher_target == "$harness_binary" ]]; then
  printf '[FAIL] O cenario nao reproduziu a cadeia intermediaria criada pelo NPM.\n' >&2
  exit 1
fi

printf '[PASS] A cadeia de links do harness resolve para %s.\n' "$launcher_target"
