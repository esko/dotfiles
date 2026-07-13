#!/usr/bin/env bash
set -euo pipefail

# SSH transport (with fail2ban) is the container's long-running supervisor.
# Agent desktops are created on demand through agent-workspace-linux MCP/CLI,
# not at container boot. See docs/synology-dev-container.md.
exec /usr/local/bin/start-sshd.sh
