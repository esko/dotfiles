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
rg -q -U 'NIX_DARWIN#darwin-rebuild[\s\S]*ensure_login_shell[\s\S]*run_install_node_tools' "$update"
rg -q '/etc/profiles/per-user/\$\{USER\}/bin' "$update"

rg -q --fixed-strings 'https://cache.numtide.com' "$update"
rg -q --fixed-strings 'niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=' "$update"
rg -q --fixed-strings 'NIX_CACHE_OPTS' "$update"
rg -q --fixed-strings 'configure_nix_cache_opts' "$update"
rg -q --fixed-strings 'numtide_cache_in_nix_config' "$update"
rg -q --fixed-strings 'accept-flake-config' "$update"
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
