#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
secrets_module="$repo_root/modules/shared/secrets.nix"
manifest="$repo_root/secrets/manifest.nix"
bootstrap="$repo_root/scripts/bootstrap-secrets.sh"
render="$repo_root/scripts/render-deployment-env.sh"

for token in dotfiles.secrets secrets/manifest.nix tailscale_auth_key consumers shared-env bootstrap-secrets; do
  rg -q --fixed-strings "$token" "$secrets_module" "$manifest" "$bootstrap" "$render"
done

for token in run-deployment-consumers manifest-common sops_load_env_secret; do
  rg -q --fixed-strings "$token" "$repo_root/scripts" "$repo_root/update.sh"
done

for token in bootstrap-secrets ssh env render-deployment-env sops-common; do
  rg -q --fixed-strings "$token" "$repo_root/flake.nix" "$repo_root/scripts"
done

rg -q --fixed-strings 'bootstrap_env_if_needed' "$repo_root/scripts/sync-deployment-secrets.sh"
rg -q --fixed-strings 'sops_resolve_env_value' "$repo_root/scripts/lib/sops-common.sh"
rg -q --fixed-strings 'sops_decrypt_shared_env_secret' "$repo_root/scripts/lib/sops-common.sh"
rg -q --fixed-strings 'shared.env' "$manifest"
rg -q --fixed-strings 'sops_load_env_secret' "$repo_root/scripts/lib/tailscale-common.sh"
rg -q --fixed-strings 'run_deployment_consumers_for_target' "$repo_root/update.sh" "$repo_root/modules/shared/secrets.nix"

if [[ -f "$repo_root/modules/shared/ssh.nix" || -f "$repo_root/modules/linux/ssh.nix" ]]; then
  printf '%s\n' 'legacy ssh modules must be removed in favor of modules/shared/secrets.nix' >&2
  exit 1
fi

if command -v nix >/dev/null 2>&1; then
  nix eval --raw "$repo_root#secretsManifest.envKeys.tailscale_auth_key.runtime" | rg -q 'TAILSCALE_AUTHKEY'
fi

printf '%s\n' 'secrets static checks passed'
