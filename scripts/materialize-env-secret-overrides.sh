#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib/sops-common.sh
source "$repo_root/scripts/lib/sops-common.sh"
# shellcheck source=lib/manifest-common.sh
source "$repo_root/scripts/lib/manifest-common.sh"

usage() {
  cat <<'EOF'
Usage: materialize-env-secret-overrides DEPLOYMENT

When a deployment declares a shared env key and also stores a per-host override
in secrets/hosts/<deployment>.yaml, copy that override into the decrypted env
path after Home Manager deploys the shared value.
EOF
}

deployment=""
while (($#)); do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      deployment=$1
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

if ! command -v sops >/dev/null 2>&1; then
  exit 0
fi

env_dir="${DOTFILES_ENV_SECRETS_DIR:-$HOME/.config/dotfiles/secrets/env}"
mkdir -p "$env_dir"
chmod 700 "$env_dir"

while IFS= read -r env_key; do
  [[ -n "$env_key" ]] || continue
  manifest_env_key_shared "$env_key" || continue
  if value=$(sops_decrypt_env_secret "$deployment" "$env_key" 2>/dev/null); then
    umask 077
    printf '%s' "$value" >"$env_dir/$env_key"
    chmod 400 "$env_dir/$env_key"
  fi
done < <(manifest_deployment_env_keys_json "$deployment" | jq -r '.[]')
