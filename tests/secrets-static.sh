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
rg -q --fixed-strings 'run_bootstrap_secrets' "$repo_root/scripts/sync-deployment-secrets.sh"
rg -q --fixed-strings 'mkDotfilesScriptApp' "$repo_root/flake.nix"
rg -q --fixed-strings 'scriptRelPath' "$repo_root/flake.nix"
# Flake apps must exec the working-tree script, not inline it into the store.
if rg -q 'builtins.readFile ./scripts/bootstrap-secrets.sh' "$repo_root/flake.nix"; then
  printf '%s\n' 'bootstrap-secrets app must not builtins.readFile the mutable script' >&2
  exit 1
fi
rg -q --fixed-strings 'manifest_deployment_wants_ssh' "$repo_root/scripts/lib/manifest-common.sh"
rg -q --fixed-strings 'manifest_deployment_wants_ssh' "$repo_root/scripts/sync-deployment-secrets.sh"
# Flake attr paths cannot embed Nix `or`; optional fields use jq.
if rg -q 'secretsManifest\.[^"]* or ' "$repo_root/scripts"; then
  printf '%s\n' 'scripts must not put Nix `or` inside flake attr paths' >&2
  exit 1
fi
# Bootstrap must not require a host sops install before Home Manager activates.
if rg -q 'require_command sops' "$repo_root/scripts/sync-deployment-secrets.sh"; then
  printf '%s\n' 'sync-deployment-secrets must use nix run .#bootstrap-secrets, not host sops' >&2
  exit 1
fi
rg -q --fixed-strings 'sops_resolve_env_value' "$repo_root/scripts/lib/sops-common.sh"
rg -q --fixed-strings 'sops_decrypt_shared_env_secret' "$repo_root/scripts/lib/sops-common.sh"
rg -q --fixed-strings 'sops_encrypt_yaml_file' "$repo_root/scripts/lib/sops-common.sh"
rg -q --fixed-strings -- '--filename-override' "$repo_root/scripts/lib/sops-common.sh"
rg -q --fixed-strings 'sops_encrypt_yaml_file' "$repo_root/scripts/bootstrap-secrets.sh"
rg -q --fixed-strings 'shared.env' "$manifest"
rg -q --fixed-strings 'sops_load_env_secret' "$repo_root/scripts/lib/tailscale-common.sh"
rg -q --fixed-strings 'run_deployment_consumers_for_target' "$repo_root/update.sh" "$repo_root/modules/shared/secrets.nix"
rg -q --fixed-strings '90-dotfiles-peers.conf' "$secrets_module"
rg -q --fixed-strings 'peerAuthorizedKeys' "$secrets_module"
rg -q --fixed-strings 'sshHostName' "$manifest"
rg -q --fixed-strings 'Include ~/.ssh/config.d' "$repo_root/ssh/.ssh/config"

if [[ -f "$repo_root/modules/shared/ssh.nix" || -f "$repo_root/modules/linux/ssh.nix" ]]; then
  printf '%s\n' 'legacy ssh modules must be removed in favor of modules/shared/secrets.nix' >&2
  exit 1
fi

if rg -q 'IdentityFile ~/.ssh/id_rsa' "$repo_root/ssh/.ssh/config"; then
  printf '%s\n' 'hand SSH config must not point at legacy id_rsa' >&2
  exit 1
fi

if command -v nix >/dev/null 2>&1; then
  nix eval --raw "$repo_root#secretsManifest.envKeys.tailscale_auth_key.runtime" | rg -q 'TAILSCALE_AUTHKEY'
fi

printf '%s\n' 'secrets static checks passed'
