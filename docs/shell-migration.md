# Fish to zsh migration

The shared Home Manager profile uses zsh on every target. Crostini is the
current Linux validation host; Baguette is the future host migration target.
The intent is to
preserve the daily Fish workflow while using the zsh modules from
`kunchenguid/dotfiles` as the baseline:

- Home Manager enables zsh completion, autosuggestions, syntax highlighting,
  shared history, and Starship.
- Fish abbreviations become zsh aliases for safe file operations, `eza`, `bat`,
  `fd`, `rg`, Git, Lefthook, and Zellij.
- `backup`, `extract`, `mkcd`, and `rfv` are zsh functions with argument checks.
- `fnm`, Bun, FZF, and the editor key binding initialize only when their
  binaries are present, keeping non-interactive shells safe.
- The untracked `agy` Fish completion is represented by a zsh `_arguments`
  completion. The Fish source remains available as a reference until agy
  publishes an upstream completion contract.

## Package boundary

`modules/shared/home.nix` installs portable CLI tools that are available in
nixpkgs, including the approved shared list (`rg`, `fd`, `fzf`, `eza`, `bat`,
`zoxide`, `git`, `gh`, `age`, `jq`, `delta`, `btop`, `micro`, `yazi`, `rsync`,
`mosh`, `shellcheck`, `lefthook`, `lazygit`, `cmake`, Rust, Go, Zig, fnm, pnpm,
uv, Python, pipx, and the audited diagnostics/archive tools). `chafa` is
intentionally excluded. `unrar` remains an external optional dependency
because nixpkgs marks it unfree and the shared flake does not enable unfree
packages globally; `extract` uses it automatically when present.

Fast-moving agent CLIs (`codex`, Claude Code, Gemini CLI, Jules,
`agent-browser`, command-code, hunkdiff, portless, Cursor Agent, Antigravity,
Athas, Herdr, pass-cli, and agy) are represented as optional nixpkgs attrs when
the selected channel provides them. Otherwise install them with their upstream
installer or npm/pip tool; Home Manager does not run network installers during
activation.

GUI applications (Cursor, VS Code, Chrome, and other approved GUI intent) stay
in Darwin/Linux host modules and are deliberately absent from this shared
profile. Docker, keyrings, device integration, and desktop services likewise
remain outside Debian container profiles.

## Verification

With Nix installed, evaluate all profiles and inspect the generated shell:

```sh
nix flake check
nix build .#homeConfigurations.crostini.activationPackage
nix build .#homeConfigurations.baguette.activationPackage
nix build .#homeConfigurations.debianTrixie.activationPackage
nix build .#darwinConfigurations.mini.system
home-manager switch --flake .#crostini
zsh -lic 'typeset -f backup extract mkcd rfv; alias | rg "^(ls|ll|g|zj)="'
```

Do not switch the login shell until the aliases and functions have been tested
in an interactive terminal. The old Fish implementation was removed from the
active tree; Git history remains available if a behavior needs to be recovered
while the zsh profile is accepted on Crostini and Baguette.
