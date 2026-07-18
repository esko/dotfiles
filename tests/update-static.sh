#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
update="$repo_root/update.sh"

for token in bootstrap-secrets sync-deployment-secrets sops_resolve_env_value; do
  rg -q --fixed-strings "$token" "$update" "$repo_root/scripts"
done

for path in "$update" "$repo_root/scripts/build-synology-dev.sh" \
  "$repo_root/scripts/sync-deployment-secrets.sh" \
  "$repo_root/scripts/tailscale-join.sh" \
  "$repo_root/scripts/run-deployment-consumers.sh"; do
  test -x "$path"
done

rg -q --fixed-strings 'run_deployment_consumers_for_target' "$update"
rg -q --fixed-strings 'NIX_DARWIN#darwin-rebuild' "$update"
rg -q --fixed-strings 'resolve_activation_pins' "$update"
rg -q --fixed-strings 'github_uri_from_lock' "$update"
rg -q --fixed-strings '#system-manager' "$update"
rg -q --fixed-strings 'SYSTEM_MANAGER="$repo_root#system-manager"' "$update"
# Must not resolve system-manager to a github: URI (loads their nixConfig warnings).
if rg -q 'github_uri_from_lock system-manager' "$update"; then
  echo 'update.sh must run system-manager via the local flake app' >&2
  exit 1
fi
rg -q -U 'sudo "\$nix_bin" run[\s\S]*NIX_DARWIN#darwin-rebuild[\s\S]*run_install_node_tools' "$update"
# Numtide host-cache nag is Linux/Baguette-only; Mini must not get that note.
rg -q --fixed-strings 'uname -s' "$update"
rg -q --fixed-strings 'baguette|synology)' "$update"
rg -q --fixed-strings 'run_install_umans' "$update"
rg -q --fixed-strings -- '--skip-umans' "$update"
rg -q --fixed-strings 'install-umans.sh' "$update"
if rg -q 'ensure_login_shell' "$update"; then
  echo 'update.sh must not duplicate nix-darwin login-shell activation' >&2
  exit 1
fi
rg -q '/etc/profiles/per-user/\$\{USER\}/bin' "$update"

rg -q --fixed-strings 'https://cache.numtide.com' "$update"
rg -q --fixed-strings 'niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=' "$update"
rg -q --fixed-strings 'NIX_CACHE_OPTS' "$update"
rg -q --fixed-strings 'configure_nix_cache_opts' "$update"
rg -q --fixed-strings 'numtide_cache_in_nix_config' "$update"
rg -q --fixed-strings 'enable-numtide-cache.sh' "$update"
# Restricted trust options only warn for unprivileged Determinate users.
if rg -q '[[:space:]]--accept-flake-config\b' "$update"; then
  echo 'update.sh must not pass --accept-flake-config on untrusted Determinate hosts' >&2
  exit 1
fi
if rg -q '[[:space:]]--option[[:space:]]+extra-trusted-public-keys\b' "$update"; then
  echo 'update.sh must not pass extra-trusted-public-keys client options' >&2
  exit 1
fi
# Apply path must not force a separate nix build before system-manager switch.
if rg -q -U 'if "\$check_only"; then[\s\S]*check_target[\s\S]*apply_target' "$update"; then
  :
else
  echo 'update.sh must run check_target only for --check-only' >&2
  exit 1
fi
if rg -q -U 'check_target "\$resolved_target"\nif "\$check_only"' "$update"; then
  echo 'update.sh must not always build before apply' >&2
  exit 1
fi

printf '%s\n' 'update.sh static checks passed'
