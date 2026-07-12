#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install-node-tools [--with-browser]

Install or update the shared Node-based CLI tools from their published npm
packages into the user-owned npm prefix. No source checkout or local Nix build
is used.

Options:
  --with-browser  Also download the browser runtime used by agent-browser.
  -h, --help      Show this help.
EOF
}

with_browser=false
case "${1:-}" in
  "")
    ;;
  --with-browser)
    with_browser=true
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  printf '%s\n' "Do not run this installer as root or through sudo." >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  printf '%s\n' "npm is required. Activate the Home Manager profile first." >&2
  exit 1
fi

prefix="${NPM_CONFIG_PREFIX:-$HOME/.local}"
export NPM_CONFIG_PREFIX="$prefix"
export PATH="$prefix/bin:$PATH"
mkdir -p "$prefix/bin"

packages=(
  "agent-browser@latest"
  "@openai/codex@latest"
  "@anthropic-ai/claude-code@latest"
  "@google/gemini-cli@latest"
  "@google/jules@latest"
  "command-code@latest"
  "hunkdiff@latest"
  "portless@latest"
)

printf 'Installing Node CLI packages into %s\n' "$prefix"
npm install --global --no-audit --no-fund "${packages[@]}"

if "$with_browser"; then
  agent-browser install
else
  cat <<'EOF'

The agent-browser CLI is installed. To download its managed browser runtime:
  agent-browser install

On a fresh Debian host, use this if browser libraries are missing:
  agent-browser install --with-deps
EOF
fi

printf '\nInstalled commands:\n'
for command_name in agent-browser codex claude gemini jules cmd hunk portless; do
  if command -v "$command_name" >/dev/null 2>&1; then
    printf '  %-15s %s\n' "$command_name" "$(command -v "$command_name")"
  else
    printf '  %-15s %s\n' "$command_name" "not found on PATH"
  fi
done
