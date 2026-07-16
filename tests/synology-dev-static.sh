#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
flake="$repo_root/flake.nix"
dockerfile="$repo_root/Dockerfile.synology-dev"
dockerignore="$repo_root/.dockerignore"
compose="$repo_root/compose/synology-dev.compose.yaml"
root_compose="$repo_root/docker-compose.yml"
guide="$repo_root/docs/synology-dev-container.md"

for required_file in "$flake" "$dockerfile" "$dockerignore" "$compose" "$root_compose" "$guide"; do
  if [[ ! -f "$required_file" ]]; then
    printf 'required Synology dev-container file is missing: %s\n' "$required_file" >&2
    exit 1
  fi
done

if ! cmp -s "$compose" "$root_compose"; then
  printf '%s\n' 'root docker-compose.yml must stay in sync with the Synology compose file' >&2
  exit 1
fi

if rg -q -- '- [^:]+:/home/esko[[:space:]]*$' "$compose"; then
  printf '%s\n' 'Compose must not persist the image-owned Home Manager home' >&2
  exit 1
fi
for mutable_path in \
  /home/esko/.cache \
  /home/esko/.local/share \
  /home/esko/.local/state \
  /home/esko/.codex \
  /home/esko/.pi \
  /home/esko/.gemini \
  /home/esko/.reasonix \
  /var/lib/tailscale; do
  rg -q --fixed-strings ":${mutable_path}" "$compose"
done

# The public build seam is a Nix root filesystem consumed by a multi-stage
# Docker build. Keep these checks at that boundary rather than prescribing the
# internal module or package layout.
rg -q 'packages\.\$\{linuxSystem\}.*synologyDevRoot|packages\.x86_64-linux.*synologyDevRoot|synologyDevRoot[[:space:]]*=' "$flake"
rg -q 'build[[:space:]].*synologyDevRoot' "$dockerfile"
rg -qi '^FROM[[:space:]].*[[:space:]]AS[[:space:]]' "$dockerfile"
rg -qi '^COPY[[:space:]].*--from=' "$dockerfile"
rg -q '/tmp/synology-dev-root/lib64 /lib64' "$dockerfile"
rg -qi '^USER[[:space:]]+(esko|1026([:]100)?)' "$dockerfile"
rg -qi '^WORKDIR[[:space:]]+/workspace' "$dockerfile"
rg -q 'llmAgents\.url[[:space:]]*=[[:space:]]*"github:numtide/llm-agents\.nix"' "$flake"
rg -q --fixed-strings 'opencode-linux-x64-baseline.tar.gz' "$flake"
rg -q 'synologyPkgs[[:space:]]*=.*linuxPkgs\.extend' "$flake"
rg -q 'bun[[:space:]]*=.*packages/bun-baseline\.nix' "$flake"
rg -q 'herdr[[:space:]]*=[[:space:]]*linuxLlmAgentPkgs\.herdr' "$flake"
rg -q 'reasonixAgent[[:space:]]*=[[:space:]]*linuxLlmAgentPkgs\.reasonix' "$flake"
rg -q --fixed-strings '"grok"' "$repo_root/modules/shared/llm-agents.nix"
# Agents ship via home.path; do not re-pass them into the image buildEnv.
if rg -q 'antigravityCli|codexAgent|grokAgent|piAgent|herdrAgent' "$repo_root/packages/synology-dev-root.nix"; then
  echo 'synology-dev-root must not re-add agents already provided by home.path' >&2
  exit 1
fi
rg -q --fixed-strings 'https://cache.numtide.com' "$dockerfile"
rg -q --fixed-strings 'niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=' "$dockerfile"
rg -q 'OPENCODE_DISABLE_AUTOUPDATE=true' "$dockerfile"
rg -q 'OPENCODE_DISABLE_AUTOUPDATE:[[:space:]]*"true"' "$compose"
rg -q 'env_file:' "$compose"
rg -q 'synology-dev\.env' "$compose" "$guide"
rg -q '/dev/net/tun' "$compose"
rg -q 'TAILSCALE_AUTHKEY|TAILSCALE_HOSTNAME|TAILSCALE_SOCKET|bootstrap-secrets' "$compose" "$guide"
rg -q 'synology-dev-start-tailscale|render-deployment-env' "$repo_root/packages/synology-dev-root.nix" "$repo_root/scripts"

# These modes are part of the non-root runtime contract. Some Docker backends
# normalize modes on copied directories, so the final stage must reassert them.
rg -q '^RUN chmod 1777 /tmp' "$dockerfile"
rg -q 'chmod u\+rwx /home/esko/.cache /home/esko/.codex /home/esko/.config' "$dockerfile"

for secret_pattern in \
  'gh/.config/gh/hosts.yml' \
  '**/.env' \
  '**/*.pem' \
  '**/*.key' \
  '**/id_rsa' \
  '**/id_ed25519' \
  '/private-context/'; do
  rg -q --fixed-strings "$secret_pattern" "$dockerignore"
done

for command_name in \
  pi herdr reasonix opencode hunk yazi flow \
  mosh eternal-terminal tailscale tsshd antigravity-cli grok codex claude-code cursor-agent \
  agent-workspace-linux; do
  rg -q --glob '*.nix' \
    "\\b${command_name}\\b" \
    "$flake" "$repo_root/modules" "$repo_root/packages"
done

# The operator guide must cover the reproducible hand-off boundary. Installation
# through Synology Container Manager remains a deliberate manual GUI/root step.
for token in \
  'dotfiles-synology-dev:latest' \
  'Dockerfile.synology-dev' \
  'docker build' \
  'docker save' \
  'ssh synology' \
  '1026' \
  '100' \
  '/home/esko' \
  '/workspace' \
  '/var/lib/tailscale' \
  'TAILSCALE_AUTHKEY' \
  'bootstrap-secrets' \
  'render-deployment-env' \
  'Container Manager'; do
  rg -q --fixed-strings "$token" "$guide"
done

if command -v nix >/dev/null 2>&1; then
  nix eval --no-write-lock-file \
    "$repo_root#packages.x86_64-linux.synologyDevRoot.name" >/dev/null
fi

printf '%s\n' 'Synology dev-container static checks passed'
