#!/usr/bin/env bash

set -euo pipefail

if command -v nix >/dev/null 2>&1; then
    printf 'Nix is already installed: %s\n' "$(nix --version)"
    exit 0
fi

case "$(uname -s)" in
    Linux|Darwin) ;;
    *)
        printf 'Unsupported operating system: %s\n' "$(uname -s)" >&2
        exit 1
        ;;
esac

cat <<'EOF'
This downloads and runs the official Determinate Nix installer.
It changes host state and may require administrator approval.
Review the installer before running it on a new machine.
EOF

read -r -p 'Install Nix now? [y/N] ' answer
case "$answer" in
    y|Y|yes|YES) ;;
    *)
        printf 'Nix installation cancelled.\n'
        exit 0
        ;;
esac

curl --proto '=https' --tlsv1.2 -sSf -L \
    https://install.determinate.systems/nix \
    | sh -s -- install

printf 'Nix installation finished. Start a new shell, then run:\n'
printf '  nix flake lock\n'
printf '  nix flake check\n'
