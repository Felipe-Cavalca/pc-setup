#!/usr/bin/env bash

pcsetup_resolve_github_release_asset() {
  local repository="$1"
  local version_policy="$2"
  local asset_name="$3"
  local configured_sha256="$4"
  local require_asset_digest="$5"
  local endpoint payload tag resolved_version asset_record asset_url asset_digest resolved_sha256

  if [[ ! $repository =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    printf 'Invalid GitHub repository: %s\n' "$repository" >&2
    return 2
  fi
  if [[ $version_policy != latest && ! $version_policy =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'Invalid release version policy: %s\n' "$version_policy" >&2
    return 2
  fi
  if [[ ! $asset_name =~ ^[A-Za-z0-9._-]+$ ]]; then
    printf 'Invalid release asset name: %s\n' "$asset_name" >&2
    return 2
  fi
  if [[ -n $configured_sha256 && ! $configured_sha256 =~ ^[a-fA-F0-9]{64}$ ]]; then
    printf 'Invalid configured SHA-256 for %s.\n' "$asset_name" >&2
    return 2
  fi
  if [[ $require_asset_digest != true && $require_asset_digest != false ]]; then
    printf 'Invalid require-asset-digest value.\n' >&2
    return 2
  fi

  if [[ $version_policy == latest ]]; then
    endpoint="https://api.github.com/repos/$repository/releases/latest"
  else
    endpoint="https://api.github.com/repos/$repository/releases/tags/v$version_policy"
  fi
  payload="$(curl --fail --location --silent --show-error \
    --header 'Accept: application/vnd.github+json' \
    --header 'X-GitHub-Api-Version: 2022-11-28' \
    --user-agent 'pc-setup' \
    "$endpoint")"

  if ! tag="$(jq --exit-status --raw-output '.tag_name' <<<"$payload")" || [[ ! $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'GitHub returned an invalid stable release tag for %s.\n' "$repository" >&2
    return 1
  fi
  resolved_version="${tag#v}"
  if [[ $version_policy != latest && $resolved_version != "$version_policy" ]]; then
    printf 'Release mismatch: requested=%s resolved=%s.\n' "$version_policy" "$resolved_version" >&2
    return 1
  fi
  if ! asset_record="$(jq --exit-status --compact-output --arg name "$asset_name" \
    '[.assets[] | select(.name == $name)] | if length == 1 then .[0] else error("expected exactly one release asset") end' <<<"$payload")"; then
    printf 'Release must contain exactly one asset named %s.\n' "$asset_name" >&2
    return 1
  fi
  asset_url="$(jq --exit-status --raw-output '.browser_download_url' <<<"$asset_record")"
  if [[ $asset_url != "https://github.com/$repository/releases/download/"*"/$asset_name" ]]; then
    printf 'Release asset not found or invalid: %s.\n' "$asset_name" >&2
    return 1
  fi

  asset_digest="$(jq --raw-output '(.digest // "")' <<<"$asset_record")"
  if [[ -n $asset_digest && ! $asset_digest =~ ^sha256:[a-fA-F0-9]{64}$ ]]; then
    printf 'GitHub returned an unsupported asset digest for %s.\n' "$asset_name" >&2
    return 1
  fi
  if [[ $require_asset_digest == true && -z $asset_digest ]]; then
    printf 'GitHub did not publish the required SHA-256 digest for %s.\n' "$asset_name" >&2
    return 1
  fi

  resolved_sha256="${asset_digest#sha256:}"
  if [[ -n $configured_sha256 ]]; then
    if [[ -n $resolved_sha256 && ${configured_sha256,,} != ${resolved_sha256,,} ]]; then
      printf 'Configured and published SHA-256 differ for %s.\n' "$asset_name" >&2
      return 1
    fi
    resolved_sha256="$configured_sha256"
  fi
  if [[ ! $resolved_sha256 =~ ^[a-fA-F0-9]{64}$ ]]; then
    printf 'No trusted SHA-256 is available for %s.\n' "$asset_name" >&2
    return 1
  fi

  printf '%s\t%s\t%s\n' "$resolved_version" "$asset_url" "${resolved_sha256,,}"
}
