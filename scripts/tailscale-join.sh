#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib/sops-common.sh
source "$repo_root/scripts/lib/sops-common.sh"
# shellcheck source=lib/manifest-common.sh
source "$repo_root/scripts/lib/manifest-common.sh"
# shellcheck source=lib/tailscale-common.sh
source "$repo_root/scripts/lib/tailscale-common.sh"

CONSUMER_NAME=tailscale-join

usage() {
  cat <<'EOF'
Usage: tailscale-join DEPLOYMENT [--consumer tailscale-join]

Join the tailnet using an auth key from secrets/hosts/<deployment>.yaml.
Skips when Tailscale is already running.

Auth key resolution order:
  1. The consumer's runtime variable in the environment (see secrets/manifest.nix)
  2. sops decrypt of the consumer's envKey from the deployment's encrypted file
EOF
}

deployment=""
consumer_name=$CONSUMER_NAME

while (($#)); do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --consumer)
      consumer_name=${2:-}
      shift 2
      ;;
    *)
      if [[ -z "$deployment" ]]; then
        deployment=$1
      else
        printf 'Unexpected argument: %s\n' "$1" >&2
        usage >&2
        exit 2
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

env_key=$(manifest_consumer_env_key "$consumer_name")
if [[ -z "$env_key" ]]; then
  printf '%s\n' "Unknown consumer '$consumer_name'." >&2
  exit 2
fi

if ! manifest_eval_json ".#secretsManifest.deployments.${deployment}.env" \
  | jq -e --arg key "$env_key" 'index($key)' >/dev/null 2>&1; then
  printf 'Consumer %s is not configured for deployment %s\n' "$consumer_name" "$deployment"
  exit 0
fi

if ! command -v tailscale >/dev/null 2>&1; then
  printf '%s\n' 'tailscale is not installed on this host' >&2
  exit 1
fi

if tailscale_is_running; then
  printf 'Tailscale is already running on %s\n' "$deployment"
  tailscale status
  exit 0
fi

if ! tailscale_load_auth_key "$deployment" "$env_key"; then
  secret_file=$(sops_secret_file "$deployment")
  runtime_var=$(sops_env_runtime_variable "$env_key")
  printf '%s\n' \
    "No Tailscale auth key found in $secret_file (env.$env_key)." \
    "Run: ./update.sh --bootstrap-secrets --env ${env_key}=..." \
    "Or set ${runtime_var} in the environment." \
    >&2
  exit 1
fi

hostname=$(manifest_consumer_hostname "$deployment" "$consumer_name")
printf 'Joining Tailscale as %s\n' "$hostname"

if tailscale_run_up "$hostname"; then
  tailscale status
  exit 0
fi

printf '%s\n' 'Tailscale did not join the tailnet.' >&2
exit 1
