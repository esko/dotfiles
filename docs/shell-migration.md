# Fish to zsh migration

The shared Home Manager profile uses zsh on every target. Crostini is the
current user-level validation host; Baguette adds a System Manager declaration
for the existing Debian account's login shell. The intent is to preserve the
daily Fish workflow while using the zsh modules from `kunchenguid/dotfiles` as
the baseline:

- Home Manager enables zsh completion, autosuggestions, syntax highlighting,
  shared history, and Starship.
- Fish abbreviations become zsh aliases for safe file operations, `eza`, `bat`,
  `fd`, `rg`, Git, Lefthook, and Zellij.
- `backup`, `extract`, `mkcd`, and `rfv` are zsh functions with argument checks.
- `fnm`, FZF, and the editor key binding initialize only when their binaries are
  present, keeping non-interactive shells safe.
- Bun completions are discovered through zsh's normal `fpath`/`compinit` flow;
  Bash completion output is never evaluated inside zsh.
- The locally installed `agy` command has a native zsh `_arguments` completion.

## Shell ownership

Home Manager owns `.zshenv`, `.zshrc`, Starship, aliases, and user packages.
On Baguette, System Manager additionally declares `/usr/bin/zsh` in the existing
`esko` account's `/etc/passwd` record. Debian owns the shell binary itself.
Crostini and lightweight containers do not modify the account database.

## Package boundary

`modules/shared/home.nix` installs portable CLI tools that are available in
nixpkgs, including the approved shared list (`rg`, `fd`, `fzf`, `eza`, `bat`,
`zoxide`, `git`, `gh`, `age`, `jq`, `delta`, `btop`, `micro`, `yazi`, `rsync`,
`mosh`, `shellcheck`, `lefthook`, `lazygit`, `cmake`, Rust, Go, Zig, fnm, pnpm,
uv, Python, pipx, and the audited diagnostics/archive tools). `chafa` is
intentionally excluded. `unrar` remains optional because it is unfree;
`extract` uses it automatically when present.

Node-based global CLIs are deliberately excluded from nixpkgs. Building their
Nix derivations can compile Rust, native Node dependencies, or bundled frontend
sources even though their upstream npm packages already publish runnable code
or platform binaries. After activating Home Manager, install or update the
approved set with the active `node` runtime set to Node.js 24 or newer:

```sh
install-node-tools
```

This installs the following packages into the user-owned npm prefix
`~/.local`, which is already on `PATH`:

| Command | npm package |
| --- | --- |
| `agent-browser` | `agent-browser` |
| `codex` | `@openai/codex` |
| `claude` | `@anthropic-ai/claude-code` |
| `gemini` | `@google/gemini-cli` |
| `jules` | `@google/jules` |
| `cmd` / `command-code` | `command-code` |
| `hunk` | `hunkdiff` |
| `portless` | `portless` |

The installer is explicit rather than a Home Manager activation hook: profile
activation stays deterministic and does not perform network operations. The
script uses `@latest` because these agent CLIs move faster than the Nix channel.
Re-run it to update the complete set.

The `agent-browser` npm package supplies its platform CLI binary. Its managed
browser runtime is a separate download:

```sh
agent-browser install
# Fresh Debian host with missing browser libraries:
agent-browser install --with-deps
```

Alternatively, install the package set and browser runtime in one pass:

```sh
install-node-tools --with-browser
```

Native fast-moving tools (`agy`/Antigravity, Cursor Agent, Athas, Herdr, and
pass-cli) are not part of the npm installer. They remain optional nixpkgs
attributes when available or should use their reviewed upstream binary
installer. Do not build them from a source checkout merely to bootstrap a host.

GUI applications, Docker, keyrings, device integration, and desktop services
stay outside the shared Home Manager profile and follow each host boundary.

## Verification

With Nix installed, evaluate all profiles and inspect the generated shell:

```sh
nix flake check
nix build .#homeConfigurations.crostini.activationPackage
nix build .#systemConfigs.baguette
nix build .#homeConfigurations.debianTrixie.activationPackage
nix build .#systemConfigs.debianTrixieContainer
nix build .#darwinConfigurations.mini.system
home-manager switch --flake .#crostini
install-node-tools --help
zsh -lic 'typeset -f backup extract mkcd rfv; alias | rg "^(ls|ll|g|zj)="'
```

On Baguette, build first and use the reviewed System Manager switch. Its
preflight checks stop before mutation unless the account and Debian Zsh paths
match the declared contract. Git history remains available if a behavior needs
to be recovered while the migration is accepted.
