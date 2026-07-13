# Platform targets

This repository has deliberately different runtime targets. Keep the system
boundary explicit when adding a package or service.

| Target | Status | Profile | Owns | Does not own |
| --- | --- | --- | --- | --- |
| Crostini Debian host | **Active now** | `homeConfigurations.crostini` | shared zsh/CLI setup, Linux user files, reviewed templates | apt sources, Docker daemon, ChromeOS display plumbing, host users/devices |
| Baguette native Debian Trixie host | **Native migration target** | `systemConfigs.baguette` | existing user identity and login shell, reviewed `/etc`/systemd boundary, embedded Home Manager | kernel, bootloader, apt repositories, drivers, display manager, Docker installation |
| Lightweight Debian Trixie container | **Default container baseline** | `homeConfigurations.debianTrixie` | headless shared CLI/toolchain and private-context helper | users, `/etc`, systemd, GUI, Docker, keyrings, GPUs, host SSH keys |
| Systemd Debian Trixie container | **Explicit opt-in** | `systemConfigs.debianTrixieContainer` | container users, Nix system environment, systemd services, embedded Home Manager | host kernel, Docker daemon, host devices, host secrets |
| Synology x86_64 dev container | **Container Manager handoff** | `packages.x86_64-linux.synologyDevRoot` | shared headless CLI setup plus NAS-compatible agent, editor, file-manager, and Flow binaries | DSM, Docker daemon, systemd, host SSH keys, GUI, privileged installation |
| Mac Mini (`mini`) | **Remote macOS host** | `darwinConfigurations.mini` | nix-darwin system policy, Homebrew declarations, shared user setup | activation of disabled LaunchAgents and unreviewed system extensions |

## Why there are two container profiles

A normal OCI/dev container should be small, unprivileged, and disposable. It
usually has no systemd process, and changing `/etc/passwd` or installing system
services adds complexity without value. Use `homeConfigurations.debianTrixie`
for those images.

Use `systemConfigs.debianTrixieContainer` only when the container intentionally
behaves like a machine: systemd is PID 1, the container has the privileges and
cgroup access needed by systemd, and it owns its user database and services. A
pre-activation assertion rejects the System Manager target otherwise.

## Current operating order

1. Make and test user-level changes against Crostini.
2. Build the lightweight Trixie profile to catch headless and package-boundary
   regressions.
3. Build the Baguette System Manager derivation and inspect it before privileged
   activation. Its preflight checks require the existing `esko` account to be
   UID/GID `1000:1000`, home `/home/esko`, and Debian Zsh at `/usr/bin/zsh`.
4. Build the systemd-container profile only for images that deliberately satisfy
   its machine-like runtime contract.
5. Build and smoke-test the Synology image locally, then copy its archive and
   checksum to DSM without loading or starting it automatically.
6. Run the native Darwin build on the Mini; do not activate it from Linux.

## Profile checks

```sh
nix flake check --all-systems
nix build .#homeConfigurations.crostini.activationPackage
nix build .#systemConfigs.baguette
nix build .#homeConfigurations.debianTrixie.activationPackage
nix build .#systemConfigs.debianTrixieContainer
nix build .#packages.x86_64-linux.synologyDevRoot
# On the Mini:
nix build .#darwinConfigurations.mini.system
```

Use `switch` only after reviewing the resulting activation package and the
host-specific notes in [`linux-bootstrap.md`](linux-bootstrap.md). Building a
System Manager output does not mutate the host; `switch --sudo` is the explicit
privileged step.
