#!/usr/bin/env bash
set -euo pipefail

# Keep deployment secrets in sync: optional first-time SSH bootstrap and
# conditional env rendering when the encrypted source file changes.

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib/sops-common.sh
source "$repo_root/scripts/lib/sops-common.sh"

usage() {
  cat <<'EOF'
Usage: sync-deployment-secrets DEPLOYMENT [options]

Options:
  --bootstrap       Create missing SSH and env secrets for this deployment
  --github          Pass --github to SSH bootstrap (with --bootstrap)
  --set-origin-ssh  Pass --set-origin-ssh to SSH bootstrap (with --bootstrap)
  --env KEY=VALUE   Env secret value (repeatable; skips prompt for that key)
  -h, --help        Show this help

Env values can also come from the runtime variable name (for example
TAILSCALE_AUTHKEY) or DOTFILES_ENV_<key> in the environment.
EOF
}

deployment=""
do_bootstrap=false
add_github=false
set_origin_ssh=false
declare -a SOPS_ENV_OVERRIDES=()

while (($#)); do
  case "$1" in
    --bootstrap)
      do_bootstrap=true
      shift
      ;;
    --github)
      add_github=true
      shift
      ;;
    --set-origin-ssh)
      set_origin_ssh=true
      shift
      ;;
    --env)
      SOPS_ENV_OVERRIDES+=("${2:-}")
      shift 2
      ;;
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
SOPS_REPO_ROOT=$repo_root

manifest_wants_ssh() {
  nix eval --json ".#secretsManifest.deployments.${deployment}.ssh or false"
}

manifest_env_keys_json() {
  nix eval --json ".#secretsManifest.deployments.${deployment}.env" 2>/dev/null || printf '[]'
}

secret_file=$(sops_secret_file "$deployment")
public_key_file="$repo_root/secrets/public/${deployment}-id_ed25519.pub"
state_dir="$repo_root/dist/$deployment"
hash_file="$state_dir/.secrets-source-sha256"

file_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

ssh_secret_present() {
  [[ -f "$secret_file" ]] || return 1
  command -v sops >/dev/null 2>&1 || return 1
  sops -d --extract '["ssh"]["id_ed25519"]' "$secret_file" 2>/dev/null \
    | grep -q 'BEGIN OPENSSH PRIVATE KEY'
}

bootstrap_ssh_if_needed() {
  if [[ "$(manifest_wants_ssh)" != true ]]; then
    printf 'Secrets: %s does not use SSH keys\n' "$deployment"
    return 0
  fi

  if ssh_secret_present && [[ -f "$public_key_file" ]]; then
    printf 'Secrets: SSH material for %s is already present\n' "$deployment"
    return 0
  fi

  if ! "$do_bootstrap"; then
    printf 'Secrets: SSH material for %s is missing; re-run with --bootstrap-secrets\n' "$deployment" >&2
    return 0
  fi

  if [[ -f "$secret_file" || -f "$public_key_file" ]]; then
    printf 'Secrets: partial SSH material exists for %s; bootstrap manually\n' "$deployment" >&2
    return 1
  fi

  bootstrap_args=(ssh "$deployment")
  if "$add_github"; then
    bootstrap_args+=(--github)
  fi
  if "$set_origin_ssh"; then
    bootstrap_args+=(--set-origin-ssh)
  fi

  printf 'Secrets: bootstrapping SSH for %s\n' "$deployment"
  nix run "$repo#bootstrap-secrets" -- "${bootstrap_args[@]}"
}

bootstrap_env_if_needed() {
  local env_keys_json env_key_count env_key env_value changed=false

  if ! command -v sops >/dev/null 2>&1; then
    printf 'Secrets: sops is not available; skipping env bootstrap\n' >&2
    return 0
  fi

  env_keys_json=$(manifest_env_keys_json)
  env_key_count=$(printf '%s' "$env_keys_json" | jq 'length')
  if [[ "$env_key_count" -eq 0 ]]; then
    return 0
  fi

  while IFS= read -r env_key; do
    [[ -n "$env_key" ]] || continue

    if sops_env_secret_present "$deployment" "$env_key"; then
      printf 'Secrets: env.%s for %s is already present\n' "$env_key" "$deployment"
      continue
    fi

    if ! "$do_bootstrap"; then
      printf 'Secrets: env.%s for %s is missing; re-run with --bootstrap-secrets\n' "$env_key" "$deployment" >&2
      continue
    fi

    if ! env_value=$(sops_resolve_env_value "$env_key"); then
      return 1
    fi

    printf 'Secrets: storing env.%s for %s\n' "$env_key" "$deployment"
    sops_upsert_env_secret "$deployment" "$env_key" "$env_value"
    changed=true
  done < <(printf '%s' "$env_keys_json" | jq -r '.[]')

  if "$changed"; then
    sops_stage_deployment_secrets "$deployment"
  fi
}

render_env_if_changed() {
  local env_keys_json env_key_count current_hash previous_hash shared_file shared_hash

  if ! command -v sops >/dev/null 2>&1; then
    printf 'Secrets: sops is not available; skipping env render\n' >&2
    return 0
  fi

  env_keys_json=$(manifest_env_keys_json)
  env_key_count=$(printf '%s' "$env_keys_json" | jq 'length')
  if [[ "$env_key_count" -eq 0 ]]; then
    printf 'Secrets: %s has no env secrets to render\n' "$deployment"
    return 0
  fi

  if ! while IFS= read -r env_key; do
    [[ -n "$env_key" ]] || continue
    sops_env_secret_present "$deployment" "$env_key" && exit 0
  done < <(printf '%s' "$env_keys_json" | jq -r '.[]'); then
    return 0
  fi

  mkdir -p "$state_dir"
  current_hash=""
  if [[ -f "$secret_file" ]]; then
    current_hash+=$(file_sha256 "$secret_file")
  fi
  shared_file=$(sops_shared_secret_file)
  if [[ -f "$shared_file" ]]; then
    current_hash+=$(file_sha256 "$shared_file")
  fi
  if [[ -z "$current_hash" ]]; then
    return 0
  fi

  previous_hash=""
  if [[ -f "$hash_file" ]]; then
    previous_hash=$(tr -d '[:space:]' <"$hash_file")
  fi

  if [[ "$current_hash" = "$previous_hash" ]]; then
    printf 'Secrets: env render skipped for %s (source unchanged)\n' "$deployment"
    return 0
  fi

  printf 'Secrets: rendering env file for %s\n' "$deployment"
  "$repo_root/scripts/render-deployment-env.sh" "$deployment"
  printf '%s\n' "$current_hash" >"$hash_file"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Required command is not available: %s\n' "$1" >&2
    exit 1
  fi
}

require_command nix
require_command jq
if "$do_bootstrap"; then
  require_command sops
fi

bootstrap_ssh_if_needed
bootstrap_env_if_needed
render_env_if_changed
