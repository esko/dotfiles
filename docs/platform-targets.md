# Platform targets

This repository has deliberately different runtime targets. Keep the system
boundary explicit when adding a package or service.

| Target | Status | Profile | Owns | Does not own |
| --- | --- | --- | --- | --- |
| Baguette native Debian Trixie host | **Active Linux host** | `systemConfigs.baguette` | existing user identity and login shell, reviewed `/etc`/systemd boundary, embedded Home Manager | kernel, bootloader, apt repositories, drivers, display manager, Docker installation |
| Synology x86_64 dev container | **Container Manager handoff** | `packages.x86_64-linux.synologyDevRoot` | shared headless CLI setup plus NAS-compatible agent, editor, file-manager, and Flow binaries | DSM, Docker daemon, systemd, host SSH keys, GUI, privileged installation |
| Mac Mini (`mini`) | **Remote macOS host** | `darwinConfigurations.mini` | nix-darwin system policy, Homebrew declarations, shared user setup | activation of disabled LaunchAgents and unreviewed system extensions |

## Current operating order

1. Make and test user-level changes on Baguette.
2. Build the Baguette System Manager derivation and inspect it before privileged
   activation. Its preflight checks require the existing `esko` account to be
   UID/GID `1000:1000`, home `/home/esko`, and Debian Zsh at `/usr/bin/zsh`.
3. Build and smoke-test the Synology image locally, then copy its archive and
   checksum to DSM without loading or starting it automatically.
4. Run the native Darwin build on the Mini; do not activate it from Linux.

## Profile checks

```sh
nix flake check --all-systems
nix build .#systemConfigs.baguette
nix build .#packages.x86_64-linux.synologyDevRoot
# On the Mini:
nix build .#darwinConfigurations.mini.system
```

Use `switch` only after reviewing the resulting activation package and the
host-specific notes in [`linux-bootstrap.md`](linux-bootstrap.md). Building a
System Manager output does not mutate the host; `switch --sudo` is the explicit
privileged step.
