#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
module="$repo_root/modules/shared/home.nix"
init="$repo_root/modules/shared/zsh/init.zsh"

for token in 'programs.zsh' 'programs.starship' 'programs.zellij' 'ripgrep' 'zoxide' 'lazygit' 'lefthook' 'delta' 'mosh' 'bun' 'home.sessionPath'; do
  rg -q --fixed-strings "$token" "$module"
done

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
