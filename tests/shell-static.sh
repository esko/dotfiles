#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
module="$repo_root/modules/shared/home.nix"
init="$repo_root/modules/shared/zsh/init.zsh"
node_tools_installer="$repo_root/scripts/install-node-tools.sh"

for token in 'programs.zsh' 'programs.starship' 'programs.zellij' 'ripgrep' 'zoxide' 'lazygit' 'lefthook' 'delta' 'mosh' 'tailscale' 'bun' 'home.sessionPath'; do
  rg -q --fixed-strings "$token" "$module" "$init"
done

for package in agent-browser @openai/codex @anthropic-ai/claude-code \
  @google/gemini-cli @google/jules command-code hunkdiff portless; do
  rg -q --fixed-strings "${package}@latest" "$node_tools_installer"
done

for command_name in agent-browser codex claude gemini jules cmd hunk portless; do
  rg -q "for command_name in .*\b${command_name}\b" "$node_tools_installer"
done

if rg -q --fixed-strings 'npx --yes' "$module" "$init"; then
  echo 'shared shell configuration must not use the obsolete npx fallback' >&2
  exit 1
fi

for function_name in backup extract mkcd rfv; do
  rg -q "^${function_name}[[:space:]]*\\(\\)" "$init"
done

if command -v zsh >/dev/null 2>&1; then
  zsh -n "$init"
fi

if command -v nix-instantiate >/dev/null 2>&1; then
  nix-instantiate --parse "$module" >/dev/null
fi

printf '%s\n' 'shared shell static checks passed'
