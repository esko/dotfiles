#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
secrets_module="$repo_root/modules/shared/secrets.nix"
secrets_modules="$repo_root/modules/shared/secrets"
stow_migration="$repo_root/modules/shared/stow-migration.nix"
manifest="$repo_root/secrets/manifest.nix"
bootstrap="$repo_root/scripts/bootstrap-secrets.sh"
render="$repo_root/scripts/render-deployment-env.sh"

for token in dotfiles.secrets secrets/manifest.nix tailscale_auth_key consumers shared-env bootstrap-secrets; do
  rg -q --fixed-strings "$token" "$secrets_module" "$secrets_modules" "$manifest" "$bootstrap" "$render"
done

for token in run-deployment-consumers manifest-common sops_load_env_secret; do
  rg -q --fixed-strings "$token" "$repo_root/scripts" "$repo_root/update.sh"
done

for token in bootstrap-secrets ssh env render-deployment-env sops-common; do
  rg -q --fixed-strings "$token" "$repo_root/flake.nix" "$repo_root/scripts"
done

rg -q --fixed-strings 'bootstrap_env_if_needed' "$repo_root/scripts/sync-deployment-secrets.sh"
rg -q --fixed-strings 'run_bootstrap_secrets' "$repo_root/scripts/sync-deployment-secrets.sh"
rg -q --fixed-strings 'mkDotfilesScriptApp' "$repo_root/flake.nix" "$repo_root/nix"
rg -q --fixed-strings 'scriptRelPath' "$repo_root/flake.nix" "$repo_root/nix"
# Flake apps must exec the working-tree script, not inline it into the store.
if rg -q 'builtins.readFile .*scripts/bootstrap-secrets.sh' "$repo_root/flake.nix" "$repo_root/nix"; then
  printf '%s\n' 'bootstrap-secrets app must not builtins.readFile the mutable script' >&2
  exit 1
fi
rg -q --fixed-strings 'manifest_deployment_wants_ssh' "$repo_root/scripts/lib/manifest-common.sh"
rg -q --fixed-strings 'manifest_deployment_wants_ssh' "$repo_root/scripts/sync-deployment-secrets.sh"
# Flake attr paths cannot embed Nix `or`; optional fields use jq.
if rg -q 'secretsManifest\.[^\"]* or ' "$repo_root/scripts"; then
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
# Status text must not pollute captured age recipients.
rg -q --fixed-strings 'Creating the local age identity' "$repo_root/scripts/lib/sops-common.sh"
rg -q 'Creating the local age identity.*>&2' "$repo_root/scripts/lib/sops-common.sh"
# Committed recipients must be bare age1… keys.
for recipient_file in "$repo_root"/secrets/age-recipients/*.txt; do
  [[ -f "$recipient_file" ]] || continue
  content=$(tr -d '[:space:]' <"$recipient_file")
  if [[ "$content" != age1* ]]; then
    printf 'invalid age recipient in %s\n' "$recipient_file" >&2
    exit 1
  fi
done
if rg -q 'Creatingthelocalageidentity' "$repo_root/.sops.yaml" \
  "$repo_root"/secrets/age-recipients/*.txt 2>/dev/null; then
  printf 'polluted age recipient text found in sops config or recipients\n' >&2
  exit 1
fi
rg -q --fixed-strings 'sops_encrypt_yaml_file' "$repo_root/scripts/bootstrap-secrets.sh"
rg -q --fixed-strings 'shared.env' "$manifest"
rg -q --fixed-strings 'sops_load_env_secret' "$repo_root/scripts/lib/tailscale-common.sh"
rg -q --fixed-strings 'run_deployment_consumers_for_target' "$repo_root/update.sh" "$secrets_module" "$secrets_modules"
rg -q --fixed-strings '90-dotfiles-peers.conf' "$secrets_module" "$secrets_modules"
rg -q --fixed-strings 'peerAuthorizedKeys' "$secrets_module" "$secrets_modules"
# Must not chmod the HM nix-store symlink (breaks Darwin activation as root).
if rg -q 'chmod 600.*authorized_keys' "$secrets_module" "$secrets_modules"; then
  echo 'secrets.nix must not chmod HM-managed authorized_keys' >&2
  exit 1
fi
# force avoids stale *.home-manager-backup blocking switch on Mini/Baguette.
rg -q 'authorized_keys\".*force = true|force = true' "$secrets_module" "$secrets_modules"
rg -q --fixed-strings 'home.file.".ssh/authorized_keys"' "$secrets_module" "$secrets_modules"
# Private key chmod must skip symlinks; never chmod HM-managed *.pub.
rg -q --fixed-strings 'if [[ -f "$HOME/.ssh/id_ed25519" && ! -L "$HOME/.ssh/id_ed25519" ]]' "$secrets_module" "$secrets_modules"
rg -q --fixed-strings 'entryAfter [ "writeBoundary" "sops-nix" ]' "$secrets_module" "$secrets_modules"
if rg -q 'chmod 644.*id_ed25519\.pub' "$secrets_module" "$secrets_modules"; then
  echo 'secrets.nix must not chmod HM-managed id_ed25519.pub' >&2
  exit 1
fi
# Darwin sops-nix must not race setupLaunchAgents and must execute the original
# declarative Program with its launchd EnvironmentVariables. The installer uses
# getconf DARWIN_USER_TEMP_DIR, so native macOS paths must remain available.
# Keep that minimal launchd environment in a subshell so it cannot remove
# gettext or other Nix tools from the remaining Home Manager activation.
darwin_activation="$secrets_modules/darwin-activation.nix"
for token in \
  'setupLaunchAgents' \
  'org.nix-community.home.sops-nix.plist' \
  'Mic92/sops-nix#910' \
  'config.launchd.agents."sops-nix".config' \
  'EnvironmentVariables' \
  'DARWIN_USER_TEMP_DIR' \
  'activation_path="$PATH"' \
  'export PATH="$activation_path' \
  'bootout --wait' \
  '/usr/bin:/bin:/usr/sbin:/sbin'; do
  rg -q --fixed-strings "$token" "$darwin_activation"
done
if rg -q --fixed-strings '/usr/bin/plutil' "$darwin_activation"; then
  echo 'Darwin sops activation must use declarative launchd config, not parse generated plists' >&2
  exit 1
fi
if rg -q --fixed-strings 'launchctl kickstart' "$darwin_activation"; then
  echo 'Darwin sops activation must not immediately run the installer twice' >&2
  exit 1
fi
rg -q --fixed-strings 'sshHostName' "$manifest"
rg -q --fixed-strings 'defaultEnvKeys' "$secrets_module" "$secrets_modules"
rg -q --fixed-strings 'hasSharedSecretFile' "$secrets_module" "$secrets_modules"
rg -q --fixed-strings 'Include ~/.ssh/config.d' "$repo_root/ssh/.ssh/config"
rg -q --fixed-strings 'Proc-Type|DEK-Info' "$repo_root/scripts/check-llm-context-safe.sh"

# A legacy ~/.ssh Stow symlink must be copied into a real directory before HM
# writes managed files. Preserve regular files while excluding ephemeral agent
# sockets and all device/special files. The resolver must remain portable to
# BSD/macOS readlink.
for token in \
  resolveLinkTarget \
  isKnownDotfilesTarget \
  '${pkgs.rsync}/bin/rsync' \
  '--no-specials' \
  '--no-devices' \
  "--exclude '/agent/'" \
  '$HOME/.ssh'; do
  rg -q --fixed-strings -- "$token" "$stow_migration"
done
if rg -q --fixed-strings 'readlink -f' "$stow_migration"; then
  printf '%s\n' 'stow migration must not use GNU-only readlink -f' >&2
  exit 1
fi

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
