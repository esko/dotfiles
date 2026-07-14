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

printf '%s\n' 'update.sh static checks passed'
