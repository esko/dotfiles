# Nix architecture

The flake separates portable user configuration from privileged host policy:

- `homeConfigurations.crostini` is a standalone Home Manager profile. ChromeOS
  and Crostini retain ownership of users, services, devices, and system files.
- `systemConfigs.baguette` is the native Debian Trixie configuration. System
  Manager owns the reviewed root-level boundary and activates Home Manager for
  the existing `esko` account.
- `homeConfigurations.debianTrixie` is the default lightweight container
  profile. It does not require systemd or privileged activation.
- `systemConfigs.debianTrixieContainer` is an explicit machine-like container
  profile for a privileged image with systemd as PID 1.
- `darwinConfigurations.mini` is a nix-darwin system configuration for the Mac
  Mini, with Home Manager embedded for user-level files.

`modules/shared` is the common Home Manager interface. System-level Linux
settings live in `modules/linux/system.nix` and
`modules/container/system.nix`; user-level Linux settings remain in the
corresponding `home.nix` files. This mirrors the nix-darwin pattern without
pretending Debian is NixOS.

## Ownership boundaries

System Manager may manage:

- declared users, groups, and login shells
- explicitly declared files under `/etc`
- systemd units and tmpfiles
- packages exposed through `/run/system-manager/sw`
- embedded Home Manager activation

Debian continues to manage:

- the kernel and bootloader
- apt repositories and base packages
- hardware drivers and the display manager
- Docker Engine and host device access
- files outside System Manager's explicit declarations

The Baguette module deliberately uses `/usr/bin/zsh` as the account shell. The
Debian package therefore remains the stable `/etc/passwd` target, while Home
Manager owns `.zshrc`, Starship, completions, aliases, and user packages.

## System Manager compatibility pin

The flake pins System Manager commit
`96f724be6f1411286e8ad0202e3e624c10116a6d` and makes it follow the same
nixpkgs input as Home Manager. This post-1.1 revision contains the compatibility
stubs required by Home Manager 26.11 on Linux, including
`system.userActivationScripts`. The v1.1.0 tag is too old for this Home Manager
release and must not be used for activation.

## Account safety

System Manager uses userborn with mutable users. Before Baguette activation,
repository assertions verify that:

- the host is Debian Trixie on x86_64
- `esko` already exists
- UID and primary GID are `1000:1000`
- the home directory is `/home/esko`
- `/usr/bin/zsh` exists and is listed in `/etc/shells`

Passwords are not declared or placed in the Nix store. The `sudo` auxiliary
group is explicitly retained. A failed preflight stops before privileged
activation.

## Bootstrap

Nix itself is installed outside Home Manager and System Manager. First update
and review the lock file:

```sh
nix flake lock
nix flake check
```

Then evaluate the intended profiles:

```sh
nix build .#homeConfigurations.crostini.activationPackage
nix build .#systemConfigs.baguette
nix build .#homeConfigurations.debianTrixie.activationPackage
nix build .#systemConfigs.debianTrixieContainer
nix build .#darwinConfigurations.mini.system
```

Activate Baguette explicitly:

```sh
sudo apt install zsh
nix run github:numtide/system-manager/96f724be6f1411286e8ad0202e3e624c10116a6d -- \
  switch --flake "$PWD#baguette" --sudo
```

For a systemd container, run the same command with
`#debianTrixieContainer` from inside the container. The lightweight container
profile continues to use `home-manager switch`.

The Darwin configuration keeps Homebrew activation cleanup disabled. Existing
apps remain untouched until an explicit package policy is added and reviewed.

The Mac host module owns approved host applications (including the Codex,
ChatGPT, Claude, Mos, Osaurus, Termius, Kitty, Hyper, Godot, editor, browser,
VLC, and JetBrains Mono casks) plus the Xcode and KeepSolid VPN Unlimited Mac
App Store entries. `mosh`, `et` (Eternal Terminal), and `tsshd` are declared as
Homebrew formulae. ProxyBridge is retained as a documented upstream-install
intent because its signed distribution is not treated as a stable cask.
Homebrew never auto-updates, upgrades, or removes existing packages.

ProxyBridge v3.2.0 has a review-only template at
`templates/proxybridge/ProxyBridge.defaults.json`. It preserves the verified
HTTP endpoint (`synology.local:8889`) and the Codex TCP process rule without
proxy credentials, plist caches, or runtime activation. Install the official
signed package manually, approve its Network Extension in System Settings,
then review and apply the template through ProxyBridge's supported UI. Do not
use a declarative activation hook for this system extension.

The two future Mac model services are represented by disabled templates under
`templates/launchagents/`. Home Manager copies them to a review directory only;
they are not registered with `launchd`, and all paths/secret references use
placeholders. Keep `Disabled=true` until the model paths, credentials, logs,
and resource limits have been reviewed for the Mini.

## Secrets boundary

`.sops.yaml` is scaffolding only. The later SSH slice should add encrypted
material under `secrets/` using age recipients, while keeping private keys,
recovery keys, and plaintext exports out of Git. No secret files are created by
the foundation. The Darwin Home Manager module exposes an opt-in
`dotfiles.darwin.ssh` interface: enable it only after adding a real per-host
Ed25519 secret encrypted with the Mini's age recipient.

Bootstrap the secret boundary manually on each host:

1. Install `age`/`sops` and configure the host age recipient in `.sops.yaml`.
2. Add only encrypted secrets under `secrets/`; keep recovery keys and plaintext
   exports outside the repository.
3. Enable only the relevant private host overlay and build before switching.
4. Add `authorizedKeys` only when incoming SSH access is intentionally part of
   that host's role.
