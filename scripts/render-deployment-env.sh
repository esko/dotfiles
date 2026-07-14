#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib/sops-common.sh
source "$repo_root/scripts/lib/sops-common.sh"
# shellcheck source=lib/manifest-common.sh
source "$repo_root/scripts/lib/manifest-common.sh"

usage() {
  cat <<'EOF'
Usage: render-deployment-env DEPLOYMENT [OUTPUT_FILE]

Decrypt deployment and shared env secrets and write a dotenv file for the
deployment's declared env keys (see secrets/manifest.nix).

Per-deployment values override shared values. When OUTPUT_FILE is omitted,
uses dist/<deployment>/<renderEnvFile> from the manifest, or
dist/<deployment>/<deployment>.env as a fallback.
EOF
}

deployment=""
output=""

while (($#)); do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$deployment" ]]; then
        deployment=$1
      else
        output=$1
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

if ! command -v sops >/dev/null 2>&1; then
  printf '%s\n' 'sops is required to render deployment env files.' >&2
  exit 1
fi

if ! command -v nix >/dev/null 2>&1; then
  printf '%s\n' 'nix is required to read secrets/manifest.nix.' >&2
  exit 1
fi

cd "$repo_root"
SOPS_REPO_ROOT=$repo_root

env_keys_json=$(manifest_deployment_env_keys_json "$deployment")
env_key_count=$(printf '%s' "$env_keys_json" | jq 'length')
if [[ "$env_key_count" -eq 0 ]]; then
  printf '%s\n' "Deployment '$deployment' does not declare any env secrets." >&2
  exit 1
fi

if [[ -z "$output" ]]; then
  render_name=$(nix eval --raw ".#secretsManifest.deployments.${deployment}.renderEnvFile or \"\"" 2>/dev/null || true)
  if [[ -z "$render_name" ]]; then
    render_name="$deployment.env"
  fi
  output="$repo_root/dist/$deployment/$render_name"
fi

mkdir -p "$(dirname "$output")"
umask 077
: >"$output"

while IFS= read -r env_key; do
  [[ -n "$env_key" ]] || continue
  variable_name=$(sops_env_runtime_variable "$env_key")
  if ! secret_value=$(sops_load_env_secret "$deployment" "$env_key"); then
    printf '%s\n' "env.$env_key is missing from deployment and shared secrets" >&2
    exit 1
  fi
  printf '%s=%s\n' "$variable_name" "$secret_value" >>"$output"
done < <(printf '%s' "$env_keys_json" | jq -r '.[]')

chmod 600 "$output"
printf 'Wrote %s\n' "$output"
