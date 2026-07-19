# Fish to zsh migration

The shared Home Manager profile uses zsh on every target. Baguette is the
primary Linux workstation; lightweight containers use the same shared modules.

- Home Manager enables zsh completion, menu-select completion UX,
  autosuggestions, syntax highlighting, shared history, and Starship.
  [carapace](https://carapace.sh) is installed but not auto-sourced (its
  `source <(carapace _carapace zsh)` bridge hung Crostini terminals). Opt in
  with `export DOTFILES_CARAPACE=1` (cached under `~/.cache/carapace/`).
- Fish abbreviations become zsh aliases for safe file operations, `eza`, `bat`,
  `fd`, `rg`, Git, Lefthook, and Zellij.
- `backup`, `extract`, `mkcd`, and `rfv` are zsh functions with argument checks.
- Node.js and npm come from the Home Manager profile; FZF and the editor key
  binding initialize only when their binaries are present, keeping
  non-interactive shells safe.
- Bun completions are discovered through zsh's normal `fpath`/`compinit` flow;
  Bash completion output is never evaluated inside zsh.
- The locally installed `agy` command has a native zsh `_arguments` completion.

## Shell ownership

Home Manager owns `.zshenv`, `.zshrc`, Starship, aliases, and user packages.
On Baguette, System Manager additionally declares `/usr/bin/zsh` in the existing
`esko` account's `/etc/passwd` record. On the Mac Mini, nix-darwin sets the
login shell to `/bin/zsh` during activation. macOS owns that shell binary;
Home Manager owns the interactive startup files. Lightweight containers do not
modify the account database.

## Package boundary

`modules/shared/home.nix` installs portable CLI tools that are available in
nixpkgs, including the approved shared list (`rg`, `fd`, `fzf`, `eza`, `bat`,
`zoxide`, `git`, `gh`, `age`, `jq`, `delta`, `btop`, `micro`, `yazi`, `rsync`,
`mosh`, `tailscale`, `shellcheck`, `lefthook`, `lazygit`, `cmake`, Rust, Go, Zig, Node.js, npm, pnpm,
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
install-umans
```

`install-umans` installs the [Umans](https://code.umans.ai/docs) CLI
(`umans`) into `~/.local/bin` from the same upstream artifact as
`curl -fsSL https://api.code.umans.ai/cli/install.sh | bash`. `./update.sh`
runs it after activation on Baguette and Mini (`--skip-umans` to skip).

`install-node-tools` installs the following packages into the user-owned npm
prefix `~/.local`, which is already on `PATH`:

| Command | npm package |
| --- | --- |
| `agent-browser` | `agent-browser` |
| `gemini` | `@google/gemini-cli` |
| `jules` | `@google/jules` |
| `cmd` / `command-code` | `command-code` |
| `hunk` / `hunkdiff` | `hunkdiff` |
| `portless` | `portless` |

`agent` (Cursor Agent), `agy`, `claude`, `codex`, `grok` (Grok Build), and
`pi` are installed from `llm-agents.nix` on every deployment through the shared
Home Manager profile — not by `install-node-tools`. The installer still lists
them in its summary so a missing Home Manager activation is obvious. Grok's
upstream `agent` binary is dropped so `agent` stays the Cursor wrapper; invoke
Grok Build as `grok`. Re-run `./update.sh` after the flake input updates to
refresh them.

The installer is explicit rather than a Home Manager activation hook: profile
activation stays deterministic and does not perform network operations. The
script uses `@latest` because these agent CLIs move faster than the Nix channel.
Re-run it to update the complete set.

Node.js and npm come from the Home Manager profile. On hosts that used fnm
before Nix, `install-node-tools` also removes stale globals from
`~/.local/share/fnm/node-versions/*/installation` so old npm shims cannot
shadow `~/.local/bin`.

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

Native fast-moving tools are not part of the npm installer. `herdr` remains an
optional nixpkgs attribute on Linux. `athas` and `pass-cli` are absent from the
pinned channels; add them only through a reviewed upstream package or binary
installer. Do not build them from a source checkout merely to bootstrap a host.

Core agent CLIs (`agent`, `agy`, `claude`, `codex`, `grok`, and `pi`) are also
outside the npm installer. They come from `llm-agents.nix` on every deployment.

GUI applications, Docker, keyrings, device integration, and desktop services
stay outside the shared Home Manager profile and follow each host boundary.

## Verification

With Nix installed, evaluate all profiles and inspect the generated shell:

```sh
nix flake check
nix build .#systemConfigs.baguette
nix build .#packages.x86_64-linux.synologyDevRoot
nix build .#darwinConfigurations.mini.system
install-node-tools --help
zsh -lic 'typeset -f backup extract mkcd rfv; alias | rg "^(ls|ll|g|zj)="'
```

On Baguette, build first and use the reviewed System Manager switch. Its
preflight checks stop before mutation unless the account and Debian Zsh paths
match the declared contract. Git history remains available if a behavior needs
to be recovered while the migration is accepted.
