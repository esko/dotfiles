# Platform targets

This repository has four deliberately different runtime targets. Keep the
host boundary explicit when adding a package or service.

| Target | Status | Profile | Owns | Does not own |
| --- | --- | --- | --- | --- |
| Crostini Debian host | **Active now** | `homeConfigurations.crostini` | shared zsh/CLI setup, Linux user files, reviewed templates | apt sources, Docker daemon, ChromeOS display plumbing, host devices |
| Baguette containerless Debian Trixie host | **Future migration target** | `homeConfigurations.baguette` | the native Linux profile once Baguette is provisioned | assumptions about Crostini sockets, Sommelier, XKB device names, or launchers |
| Debian Trixie container | **Baseline for containers** | `homeConfigurations.debianTrixie` | headless shared CLI/toolchain and private-context helper | GUI, Docker, keyrings, GPUs, host SSH keys, display/device access |
| Mac Mini (`mini`) | **Remote macOS host** | `darwinConfigurations.mini` | nix-darwin system policy, Homebrew declarations, shared user setup | activation of disabled LaunchAgents and unreviewed system extensions |

## Current operating order

1. Make and test changes against Crostini.
2. Build the Trixie container profile to catch headless and package-boundary
   regressions.
3. Before moving to the containerless Baguette host, re-check host-owned
   display, keyboard, launcher, Docker, and GPU integration. Do not assume
   Crostini paths or services carry over. Do not substitute
   `homeConfigurations.debianTrixie`: that profile is for containers and
   intentionally omits Linux host integration.
4. Run the native Darwin build on the Mini; do not activate it from Crostini.

## Profile checks

```sh
nix flake check --all-systems
nix build .#homeConfigurations.crostini.activationPackage
nix build .#homeConfigurations.baguette.activationPackage
nix build .#homeConfigurations.debianTrixie.activationPackage
# On the Mini:
nix build .#darwinConfigurations.mini.system
```

Use `switch` only after reviewing the resulting activation package and the
host-specific notes in [`linux-bootstrap.md`](linux-bootstrap.md). A profile
build is safe to run on the current Crostini host; it does not migrate the
operating system or install host daemons.
