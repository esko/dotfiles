# Dotfiles

Cross-platform configuration managed with Nix flakes. Standalone Home Manager
owns Crostini and lightweight container user environments, System Manager owns
the native Debian/Baguette system boundary, and nix-darwin owns the Mac Mini.

## Structure

- `flake.nix`, `flake.lock`: pinned Nix inputs and host profiles
- `modules/shared/`: portable Home Manager shell, CLI, editor, and context setup
- `modules/linux/`: Baguette System Manager policy plus Linux Home Manager files
- `modules/container/`: lightweight and systemd-container profiles
- `modules/darwin/`: nix-darwin and Mac Mini Home Manager configuration
- `templates/`: review-only templates for host integration and private tools
- `docs/`: bootstrap, platform boundaries, shell migration, and context policy

The old Stow packages and Fish files have been removed from the active tree.
Their history remains available for rollback or for recovering a behavior that
has not yet been represented in the Nix modules.

## Nix workflow

On a new host, install Nix using the platform bootstrap instructions, then
review and evaluate the matching profile:

```bash
git clone https://github.com/esko/dotfiles.git ~/dotfiles
cd ~/dotfiles
nix flake check

# Crostini: standalone Home Manager
nix build .#homeConfigurations.crostini.activationPackage

# Baguette: System Manager with embedded Home Manager
nix build .#systemConfigs.baguette

# Lightweight Debian Trixie OCI/dev container
nix build .#homeConfigurations.debianTrixie.activationPackage

# Privileged Debian Trixie container with systemd as PID 1
nix build .#systemConfigs.debianTrixieContainer

# Mac Mini (run on the Mini)
nix build .#darwinConfigurations.mini.system
```

Activate Baguette only after reviewing the build and the preflight checks:

```bash
sudo apt install zsh
nix run github:numtide/system-manager/v1.1.0 -- \
  switch --flake "$PWD#baguette" --sudo
```

This activation manages the existing `esko` account's login shell, the reviewed
system boundary, and its Home Manager generation in one operation. It does not
replace Debian's kernel, bootloader, drivers, apt repositories, display manager,
or Docker installation.

After activating a Linux Home Manager profile, install the fast-moving
Node-based CLIs from their published npm packages rather than building their
nixpkgs derivations:

```bash
install-node-tools
# Also download the agent-browser managed browser runtime:
install-node-tools --with-browser
```

The installer writes only to the user-owned npm prefix under `~/.local`.
Re-running it updates the complete approved Node CLI set.

See [`docs/platform-targets.md`](docs/platform-targets.md) for the host matrix
and [`docs/linux-bootstrap.md`](docs/linux-bootstrap.md) for the Crostini to
Baguette transition and System Manager safety checks.

The architecture and secret boundary are documented in
[`docs/nix-architecture.md`](docs/nix-architecture.md) and
[`docs/llm-context.md`](docs/llm-context.md). Nix bootstrap remains explicit and
never runs during Home Manager activation.

Install Lefthook alone on an existing machine:

```bash
./scripts/install-lefthook.sh
```

SSH keys and agent context are opt-in private material. Follow the SOPS/age
instructions in [`docs/nix-architecture.md`](docs/nix-architecture.md) and
[`docs/llm-context.md`](docs/llm-context.md); never commit plaintext keys,
tokens, histories, or client state.
