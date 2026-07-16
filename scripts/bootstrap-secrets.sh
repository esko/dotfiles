#!/usr/bin/env bash
set -euo pipefail

umask 077
export LC_ALL=C

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib/sops-common.sh
source "$repo_root/scripts/lib/sops-common.sh"

usage() {
  cat <<'EOF'
Usage:
  bootstrap-secrets ssh DEPLOYMENT [--github] [--set-origin-ssh]
  bootstrap-secrets env DEPLOYMENT KEY [--value VALUE] [--stdin]
  bootstrap-secrets shared-env KEY [--value VALUE] [--stdin]

Create or update SOPS-encrypted deployment secrets in secrets/hosts/<deployment>.yaml.
Shared env secrets for all deployments live in secrets/shared.yaml.

SSH examples:
  bootstrap-secrets ssh baguette --github --set-origin-ssh
  bootstrap-secrets ssh baguette --github
  bootstrap-secrets ssh mini --github

Environment examples:
  bootstrap-secrets shared-env tailscale_auth_key --value 'tskey-auth-...'
  bootstrap-secrets env synology-dev tailscale_auth_key
  bootstrap-secrets env baguette tailscale_auth_key --value 'tskey-auth-baguette-...'

Keys and their runtime variable names are declared in secrets/manifest.nix.
Shared keys are listed under secrets/manifest.nix shared.env.
EOF
}

command_name=""
deployment=""
env_key=""
env_value=""
use_stdin=false
add_github=false
set_origin_ssh=false

while (($#)); do
  case "$1" in
    ssh|env|shared-env)
      command_name=$1
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
    --value)
      env_value=${2:-}
      shift 2
      ;;
    --stdin)
      use_stdin=true
      shift
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
      elif [[ "$command_name" = env && -z "$env_key" ]]; then
        env_key=$1
      elif [[ "$command_name" = shared-env && -z "$env_key" ]]; then
        env_key=$1
      else
        printf '%s\n' "Unexpected argument: $1" >&2
        usage >&2
        exit 2
      fi
      shift
      ;;
  esac
done

if [[ -z "$command_name" ]]; then
  usage >&2
  exit 2
fi

if [[ "$command_name" != shared-env && -z "$deployment" ]]; then
  usage >&2
  exit 2
fi

if [[ "$command_name" != shared-env ]]; then
  sops_validate_deployment_name "$deployment"
fi

cd "$repo_root"
export SOPS_REPO_ROOT=$repo_root

if [[ "$command_name" != shared-env ]]; then
  public_dir="$repo_root/secrets/public"
  public_key_file="$public_dir/${deployment}-id_ed25519.pub"
  secret_file=$(sops_secret_file "$deployment")
  recipient=$(sops_ensure_recipient "$deployment")
fi

bootstrap_ssh() {
  if [[ -e "$secret_file" || -e "$public_key_file" ]]; then
    printf '%s\n' "SSH material for '$deployment' already exists; refusing to overwrite it." >&2
    exit 1
  fi

  mkdir -p "$public_dir"

  tmp_dir=$(mktemp -d)
  cleanup() {
    rm -rf "$tmp_dir"
  }
  trap cleanup EXIT HUP INT TERM

  private_key="$tmp_dir/id_ed25519"
  plain_secret="$tmp_dir/$deployment.yaml"

  printf '%s\n' "Generating the $deployment Ed25519 key. Set a passphrase when prompted."
  ssh-keygen -t ed25519 -a 100 -C "esko@$deployment" -f "$private_key"

  {
    printf '%s\n' 'ssh:'
    printf '%s\n' '  id_ed25519: |-'
    sed 's/^/    /' "$private_key"
  } >"$plain_secret"

  # Encrypt before publishing the pubkey so a failed sops run cannot leave
  # partial SSH material that blocks retry.
  mkdir -p "$(dirname "$secret_file")"
  sops_encrypt_yaml_file "$(sops_secret_file_rel "$deployment")" "$recipient" \
    "$plain_secret" "$secret_file"

  cp "$private_key.pub" "$public_key_file"
  chmod 644 "$public_key_file"

  git add "$repo_root/.sops.yaml" \
    "$repo_root/secrets/age-recipients/$deployment.txt" \
    "$secret_file" \
    "$public_key_file"

  if "$add_github"; then
    if ! gh auth status --hostname github.com >/dev/null 2>&1; then
      gh auth login --hostname github.com --git-protocol ssh
    fi
    gh ssh-key add "$public_key_file" --title "$deployment-$(date +%Y-%m-%d)"
  fi

  if "$set_origin_ssh"; then
    origin_url=$(git remote get-url origin 2>/dev/null || true)
    case "$origin_url" in
      https://github.com/*)
        repository=${origin_url#https://github.com/}
        repository=${repository%.git}
        git remote set-url origin "git@github.com:${repository}.git"
        ;;
      git@github.com:*)
        ;;
      *)
        printf 'Origin is not a GitHub HTTPS remote; leaving it unchanged: %s\n' "$origin_url" >&2
        ;;
    esac
  fi

  cat <<EOF

Created SOPS-managed SSH material for: $deployment

Encrypted host secrets: $secret_file
Public SSH key:        $public_key_file
Public age recipient:  $repo_root/secrets/age-recipients/$deployment.txt
Local age identity:    $(sops_age_key_file)

Back up the local age identity securely. Do not commit or upload it.
Review staged files with:
  git status --short
  git diff --cached --stat
EOF
}

bootstrap_env() {
  if [[ -z "$env_key" ]]; then
    printf '%s\n' 'An environment secret key is required for the env command.' >&2
    usage >&2
    exit 2
  fi

  if ! manifest_env_key_declared "$env_key"; then
    printf '%s\n' "Unknown env key '$env_key'. Declare it in secrets/manifest.nix first." >&2
    exit 1
  fi

  if sops_env_secret_present "$deployment" "$env_key"; then
    if sops_env_secret_present_in_file "$(sops_secret_file "$deployment")" "$env_key"; then
      printf '%s\n' "env.$env_key is already present in $(sops_secret_file "$deployment")"
    else
      printf '%s\n' "env.$env_key is already present in $(sops_shared_secret_file)"
    fi
    exit 0
  fi

  if "$use_stdin"; then
    env_value=$(cat)
  elif [[ -z "$env_value" ]]; then
    # Drop caller overrides so resolve prompts / uses the environment instead.
    # shellcheck disable=SC2034
    SOPS_ENV_OVERRIDES=()
    if ! env_value=$(sops_resolve_env_value "$env_key"); then
      exit 1
    fi
  fi

  if [[ -z "$env_value" ]]; then
    printf '%s\n' 'An environment secret value is required.' >&2
    exit 1
  fi

  sops_upsert_env_secret "$deployment" "$env_key" "$env_value"
  sops_stage_deployment_secrets "$deployment"

  cat <<EOF

Stored env.$env_key in $secret_file
Runtime variable: $(sops_env_runtime_variable "$env_key")

Render deployment env files with:
  ./scripts/render-deployment-env.sh $deployment
EOF
}

bootstrap_shared_env() {
  if [[ -z "$env_key" ]]; then
    printf '%s\n' 'An environment secret key is required for the shared-env command.' >&2
    usage >&2
    exit 2
  fi

  if ! manifest_env_key_declared "$env_key"; then
    printf '%s\n' "Unknown env key '$env_key'. Declare it in secrets/manifest.nix first." >&2
    exit 1
  fi

  if ! manifest_env_key_shared "$env_key"; then
    printf '%s\n' "env.$env_key is not listed in secrets/manifest.nix shared.env." >&2
    exit 1
  fi

  if sops_env_secret_present_in_file "$(sops_shared_secret_file)" "$env_key"; then
    printf '%s\n' "env.$env_key is already present in $(sops_shared_secret_file)"
    exit 0
  fi

  if "$use_stdin"; then
    env_value=$(cat)
  elif [[ -z "$env_value" ]]; then
    # Drop caller overrides so resolve prompts / uses the environment instead.
    # shellcheck disable=SC2034
    SOPS_ENV_OVERRIDES=()
    if ! env_value=$(sops_resolve_env_value "$env_key"); then
      exit 1
    fi
  fi

  if [[ -z "$env_value" ]]; then
    printf '%s\n' 'An environment secret value is required.' >&2
    exit 1
  fi

  sops_upsert_shared_env_secret "$env_key" "$env_value"
  sops_stage_shared_secrets

  cat <<EOF

Stored shared env.$env_key in $(sops_shared_secret_file)
Runtime variable: $(sops_env_runtime_variable "$env_key")

Per-deployment overrides can still be stored with:
  nix run .#bootstrap-secrets -- env <deployment> $env_key
EOF
}

case "$command_name" in
  ssh)
    bootstrap_ssh
    ;;
  env)
    bootstrap_env
    ;;
  shared-env)
    bootstrap_shared_env
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
