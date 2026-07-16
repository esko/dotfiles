# Dotfiles

Cross-platform configuration managed with Nix flakes. System Manager owns
the native Debian/Baguette system boundary, the Synology image embeds a
container Home Manager profile, and nix-darwin owns the Mac Mini.

## Structure

- `flake.nix`, `flake.lock`: pinned Nix inputs and host profiles
- `modules/shared/`: portable Home Manager shell, CLI, editor, and context setup
- `modules/linux/`: Baguette System Manager policy plus Linux Home Manager files
- `modules/container/`: Synology image Home Manager additions
- `Dockerfile.synology-dev`: unprivileged x86_64 Synology development image
- `compose/`: deployment definitions for handoff to Container Manager
- `modules/darwin/`: nix-darwin and Mac Mini Home Manager configuration
- `templates/`: review-only templates for host integration and private tools
- `docs/`: bootstrap, platform boundaries, shell migration, and context policy

The old Stow packages and Fish files have been removed from the active tree.
Their history remains available for rollback or for recovering a behavior that
has not yet been represented in the Nix modules.

## Update

From the repository checkout, apply the matching profile on any host:

```bash
./update.sh
```

`update.sh` detects the platform (or reads `~/.config/dotfiles/target`), runs
the matching System Manager / `darwin-rebuild` activation from flake.lock pins,
installs Node CLIs where appropriate, and can hand off the Synology image:

```bash
./update.sh --pull                  # git pull, then update
./update.sh --target baguette       # force a profile and remember it
./update.sh --bootstrap-secrets       # create missing SSH secrets, render changed env files
./update.sh --bootstrap-secrets --github   # bootstrap SSH and add it to GitHub
./update.sh --synology              # build + copy the NAS dev image
./update.sh --check-only            # build/check without activating
```

First-time secret setup is part of `--bootstrap-secrets` when material is missing.
Pass env values with `--env key=value`, export `TAILSCALE_AUTHKEY` / `DOTFILES_ENV_<key>`,
or answer the prompt. Re-runs skip existing secrets and env rendering unless the
encrypted source file changed.

## Nix workflow

`./update.sh` is the day-to-day entry point. Use the commands below when you
need to inspect derivations without activating.

On a new host, install Nix using the platform bootstrap instructions, then
review and evaluate the matching profile:

```bash
git clone https://github.com/esko/dotfiles.git ~/dotfiles
cd ~/dotfiles
nix flake check

# Baguette: System Manager with embedded Home Manager (Numtide cache options)
./update.sh --check-only --target baguette

# Synology x86_64 development-container root closure
nix build .#packages.x86_64-linux.synologyDevRoot

# Mac Mini (run on the Mini)
nix build .#darwinConfigurations.mini.system
```

Activate Baguette only after reviewing the build and the preflight checks.
`./update.sh` enables Numtide's binary cache for `llm-agents.nix` and activates
in one build:

```bash
sudo apt install zsh
./update.sh --target baguette
```

This activation manages the existing `esko` account's login shell, the reviewed
system boundary, and its Home Manager generation in one operation. It does not
replace Debian's kernel, bootloader, drivers, apt repositories, display manager,
or Docker installation.

After activating a Linux Home Manager profile, install the fast-moving
Node-based CLIs from their published npm packages rather than building their
nixpkgs derivations. The installer requires the active `node` runtime to be
Node.js 24 or newer:

```bash
install-node-tools
# Also download the agent-browser managed browser runtime:
install-node-tools --with-browser
```

The installer writes only to the user-owned npm prefix under `~/.local`.
Re-running it updates the complete approved Node CLI set.

See [`docs/platform-targets.md`](docs/platform-targets.md) for the host matrix
and [`docs/linux-bootstrap.md`](docs/linux-bootstrap.md) for Baguette bootstrap
and System Manager safety checks.

The architecture and secret boundary are documented in
[`docs/nix-architecture.md`](docs/nix-architecture.md) and
[`docs/llm-context.md`](docs/llm-context.md). Nix bootstrap remains explicit and
never runs during Home Manager activation.

The Synology development image packages the shared command-line environment
plus `pi`, `herdr`, `reasonix`, `opencode`, `hunk`, `yazi`, Neurocyte Flow, `agy`,
`grok`, Codex,
and the Mosh/ET/Tailscale/tsshd remote-session helpers. Build, test,
archive, and copy it to the NAS with `./scripts/build-synology-dev.sh`; see
[`docs/synology-dev-container.md`](docs/synology-dev-container.md) for the
unprivileged runtime contract and the final manual Container Manager steps.

Install Lefthook alone on an existing machine:

```bash
./scripts/install-lefthook.sh
```

SSH keys and deployment secrets are managed through SOPS in `secrets/`. See
[`secrets/README.md`](secrets/README.md), [`docs/nix-architecture.md`](docs/nix-architecture.md),
and [`docs/llm-context.md`](docs/llm-context.md); never commit plaintext keys,
tokens, histories, or client state.
