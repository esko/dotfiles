#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
module="$repo_root/modules/shared/home.nix"
init="$repo_root/modules/shared/zsh/init.zsh"
node_tools_installer="$repo_root/scripts/install-node-tools.sh"

llm_agents_module="$repo_root/modules/shared/llm-agents.nix"

for token in 'programs.zsh' 'programs.starship' 'programs.zellij' 'ripgrep' 'zoxide' 'lazygit' 'lefthook' 'delta' 'mosh' 'tailscale' 'bun' 'home.sessionPath'; do
  rg -q --fixed-strings "$token" "$module" "$init"
done

for attr in cursor-agent antigravity-cli claude-code codex grok pi; do
  rg -q --fixed-strings "\"${attr}\"" "$llm_agents_module"
done
rg -q 'writeShellScriptBin "agent"' "$llm_agents_module"
rg -q 'rm -f "\$out/bin/agent"' "$llm_agents_module"
rg -q 'name == "grok"' "$llm_agents_module"

rg -q 'llmAgentPkgs = linuxLlmAgentPkgs' "$repo_root/flake.nix"
rg -q 'llmAgentPkgs = darwinLlmAgentPkgs' "$repo_root/flake.nix"
rg -q 'optional-packages\.nix' "$module"
rg -q 'optionalFreePackages' "$module"
rg -q 'hostPlatform.isDarwin' "$module"

editors_module="$repo_root/modules/shared/editors.nix"
rg -q 'editors\.nix' "$module"
rg -q 'programs\.gh' "$module"
rg -q 'git_protocol = "https"' "$module"
rg -q 'config/editors/cursor/settings.json' "$editors_module"
rg -q 'Application Support/Cursor' "$editors_module"
rg -q '\.config/Cursor' "$editors_module"

# Orphan Stow package trees must stay removed once HM owns them.
for orphan in git gh cursor vscode zed sublime-text; do
  if [[ -e "$repo_root/$orphan" ]]; then
    echo "orphan Stow package tree must be removed: $orphan" >&2
    exit 1
  fi
done

stow_migration="$repo_root/modules/shared/stow-migration.nix"
rg -q 'removeLegacyStowSymlinks' "$stow_migration"
rg -q 'entryBefore \[ "linkGeneration" \]' "$stow_migration"
rg -q '.config/bat' "$stow_migration"
rg -q '.config/zellij' "$stow_migration"
rg -q '.config/Cursor' "$stow_migration"
rg -q '.config/gh' "$stow_migration"

rg -q '.config/starship.toml' "$module"
rg -q 'starship/.config/starship.toml' "$module"
rg -q 'utilities/.config/bat/themes' "$module"
rg -q 'utilities/.config/micro/colorschemes' "$module"
rg -q 'manual.manpages.enable = false' "$module"
rg -q 'force = true' "$module"

for package in agent-browser @google/gemini-cli @google/jules command-code hunkdiff portless; do
  rg -q --fixed-strings "${package}@latest" "$node_tools_installer"
done

rg -q --fixed-strings 'package_bin_commands' "$node_tools_installer"
rg -q --fixed-strings 'Installed commands:' "$node_tools_installer"
for command_name in agent agy claude codex grok pi; do
  rg -q "for command_name in .*\b${command_name}\b" "$node_tools_installer"
done
rg -q --fixed-strings 'browser_runtime_present' "$node_tools_installer"
rg -q --fixed-strings 'Installed npm packages:' "$node_tools_installer"
rg -q --fixed-strings 'Agent CLIs (Home Manager / llm-agents.nix)' "$node_tools_installer"

if rg -q --fixed-strings 'npx --yes' "$module" "$init"; then
  echo 'shared shell configuration must not use the obsolete npx fallback' >&2
  exit 1
fi

if rg -q 'fnm env' "$init"; then
  echo 'shared shell configuration must not initialize fnm' >&2
  exit 1
fi

rg -q 'remove_legacy_fnm_globals' "$node_tools_installer"
rg -q 'fnm/node-versions' "$node_tools_installer"

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
