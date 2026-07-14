#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib/sops-common.sh
source "$repo_root/scripts/lib/sops-common.sh"
# shellcheck source=lib/manifest-common.sh
source "$repo_root/scripts/lib/manifest-common.sh"

usage() {
  cat <<'EOF'
Usage: run-deployment-consumers DEPLOYMENT [CONSUMER ...]

Run manifest-declared consumer scripts for a deployment. When no consumers are
named, runs every consumer whose envKey is listed on the deployment.

Consumers read env secrets directly from secrets/hosts/<deployment>.yaml via sops.
See secrets/manifest.nix for envKeys and consumers.
EOF
}

deployment=""
declare -a requested_consumers=()

while (($#)); do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -z "$deployment" ]]; then
        deployment=$1
      else
        requested_consumers+=("$1")
      fi
      shift
      ;;
  esac
done

if [[ -z "$deployment" ]]; then
  usage >&2
  exit 2
fi

sops_validate_deployment_name "$deployment"
cd "$repo_root"

if ! command -v nix >/dev/null 2>&1; then
  printf '%s\n' 'nix is required to read secrets/manifest.nix.' >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' 'jq is required to read secrets/manifest.nix.' >&2
  exit 1
fi

enabled_consumers_json=$(manifest_deployment_consumers_json "$deployment")
enabled_count=$(printf '%s' "$enabled_consumers_json" | jq 'length')

if [[ "$enabled_count" -eq 0 ]]; then
  printf 'No secret consumers configured for %s\n' "$deployment"
  exit 0
fi

run_consumer() {
  local consumer=$1 script_path

  if ! printf '%s' "$enabled_consumers_json" | jq -e --arg name "$consumer" 'index($name)' >/dev/null; then
    printf '%s\n' "Consumer '$consumer' is not enabled for deployment '$deployment'." >&2
    return 1
  fi

  script_path="$repo_root/scripts/$(manifest_consumer_script "$consumer")"
  if [[ ! -x "$script_path" ]]; then
    printf '%s\n' "Consumer script is missing or not executable: $script_path" >&2
    return 1
  fi

  printf 'Running consumer %s for %s\n' "$consumer" "$deployment"
  "$script_path" "$deployment" --consumer "$consumer"
}

if ((${#requested_consumers[@]} > 0)); then
  for consumer in "${requested_consumers[@]}"; do
    run_consumer "$consumer"
  done
else
  while IFS= read -r consumer; do
    [[ -n "$consumer" ]] || continue
    run_consumer "$consumer"
  done < <(printf '%s' "$enabled_consumers_json" | jq -r '.[]')
fi
