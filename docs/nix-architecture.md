# Nix architecture

The flake separates portable user configuration from host integration:

- `homeConfigurations.crostini` is a standalone Home Manager profile for the
  current Linux host and the future Bruschetta migration.
- `homeConfigurations.debianTrixie` is a deliberately small profile for Debian
  Trixie containers. It does not install Docker, GUI applications, keyrings, or
  device integration.
- `darwinConfigurations.mini` is a nix-darwin system configuration for the Mac
  Mini, with Home Manager embedded for user-level files.

`modules/shared` is the common interface. `modules/linux`, `modules/container`,
and `modules/darwin` are host boundaries where packages, shells, services, and
application configuration are added. Linux host/package boundaries are
documented in [`docs/linux-bootstrap.md`](linux-bootstrap.md); Home Manager
does not install host daemons or mutate apt repositories.

## Bootstrap

Nix is not assumed to be installed by the legacy `install.sh`. On a machine
with Nix enabled, first create and review the lock file:

```sh
nix flake lock
nix flake check
```

Then evaluate the intended profile:

```sh
nix build .#homeConfigurations.crostini.activationPackage
nix build .#homeConfigurations.debianTrixie.activationPackage
nix build .#darwinConfigurations.mini.system
```

The Darwin configuration keeps Homebrew activation cleanup disabled. Existing
apps remain untouched until an explicit package policy is added and reviewed.

## Secrets boundary

`.sops.yaml` is scaffolding only. The later SSH slice should add encrypted
material under `secrets/` using age recipients, while keeping private keys,
recovery keys, and plaintext exports out of Git. No secret files are created by
the foundation.
