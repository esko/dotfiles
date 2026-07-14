#!/usr/bin/env bash
set -euo pipefail

# Tailscale runs inside the container before SSH comes up. See
# docs/synology-dev-container.md.
/bin/synology-dev-start-tailscale
exec /bin/synology-dev-start-sshd
