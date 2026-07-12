# Dotfiles

Cross-platform configuration managed with Nix flakes and Home Manager. The
active Linux host is Crostini; the planned replacement host is Baguette, with
Debian Trixie as the container baseline. The Mac Mini is managed separately by
nix-darwin.

## Structure

- `flake.nix`, `flake.lock`: pinned Nix inputs and host profiles
- `modules/shared/`: portable Home Manager shell, CLI, editor, and context setup
- `modules/linux/`: Crostini/Baguette host integration and Linux-only packages
- `modules/container/`: headless Debian Trixie container profile
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
# Crostini (current host)
nix build .#homeConfigurations.crostini.activationPackage
# Baguette (future native Linux host)
nix build .#homeConfigurations.baguette.activationPackage
# Debian Trixie container baseline
nix build .#homeConfigurations.debianTrixie.activationPackage
# Mac Mini (run on the Mini)
nix build .#darwinConfigurations.mini.system
```

See [`docs/platform-targets.md`](docs/platform-targets.md) for the host matrix
and [`docs/linux-bootstrap.md`](docs/linux-bootstrap.md) for the Crostini to
Baguette transition. Host daemons, Docker, display integration, and machine-
local GUI installers remain outside Home Manager.

The architecture and secret boundary are documented in
[`docs/nix-architecture.md`](docs/nix-architecture.md) and
[`docs/llm-context.md`](docs/llm-context.md). Nix bootstrap is explicit and
never runs during Home Manager activation.

Install Lefthook alone on an existing machine:

```bash
./scripts/install-lefthook.sh
```

SSH keys and agent context are opt-in private material. Follow the SOPS/age
instructions in [`docs/nix-architecture.md`](docs/nix-architecture.md) and
[`docs/llm-context.md`](docs/llm-context.md); never commit plaintext keys,
tokens, histories, or client state.
