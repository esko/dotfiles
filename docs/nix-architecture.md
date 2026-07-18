# Nix architecture

The flake separates portable user configuration from privileged host policy:

- `systemConfigs.baguette` is the native Debian Trixie configuration. System
  Manager owns the reviewed root-level boundary and activates Home Manager for
  the existing `esko` account.
- `packages.x86_64-linux.synologyDevRoot` is the unprivileged Synology
  development-container root closure with embedded Home Manager evaluation.
- `darwinConfigurations.mini` is a nix-darwin system configuration for the Mac
  Mini, with Home Manager embedded for user-level files.

`modules/shared` is the common Home Manager interface. System-level Linux
settings live in `modules/linux/system.nix`; user-level Linux settings remain
in `modules/linux/home.nix`. Container-specific Home Manager additions for the
Synology image live in `modules/container/home.nix`. This mirrors the
nix-darwin pattern without pretending Debian is NixOS.

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

## Binary cache for llm-agents

Numtide's cache is trusted on the host, not via flake `nixConfig` (unprivileged
Determinate users cannot apply flake `trusted-public-keys`). On Baguette and
Mini run `./scripts/enable-numtide-cache.sh` so `/etc/nix/nix.custom.conf`
lists the substituter and key — that is what lets `codex` and the other
`llm-agents.nix` CLIs download prebuilt binaries instead of compiling. The
helper also sets `fallback = false` and `builders-use-substitutes = true`.
`./update.sh` refuses baguette/mini activation until that cache is trusted
(override with `--allow-builds`). The Synology Docker builder still passes
cache options as root. See `docs/linux-bootstrap.md`. System Manager must not
replace Determinate's Nix configuration.

## Bootstrap

Nix itself is installed outside Home Manager and System Manager. First update
and review the lock file:

```sh
nix flake lock
nix flake check
```

Then evaluate the intended profiles:

```sh
./update.sh --check-only
nix build .#packages.x86_64-linux.synologyDevRoot
nix build .#darwinConfigurations.mini.system
```

Activate Baguette with the day-to-day entry point (Numtide cache options, single
build):

```sh
sudo apt install zsh
./update.sh --target baguette
```

The Darwin configuration keeps Homebrew activation cleanup disabled. Existing
apps remain untouched until an explicit package policy is added and reviewed.

The Mini uses Determinate Nix, so `nix.enable = false` in
`modules/darwin/system.nix`. nix-darwin must not replace `/etc/nix` on a host
where Determinate already manages the daemon and settings. Activation also sets
the `esko` login shell from Homebrew Fish to `/bin/zsh` without replacing
`/etc/shells`. Recent nix-darwin requires root for `darwin-rebuild switch`;
`./update.sh --target mini` runs it under `sudo` (`system.primaryUser = esko`).

The Mac host module owns approved host applications (including the Codex,
ChatGPT, Claude, Mos, Hyper, Godot, editor, browser, VLC, and JetBrains Mono
casks). `mosh`, `et` (Eternal Terminal), `tailscale`, and `tsshd` are declared
as Homebrew formulae. Homebrew never auto-updates, upgrades, or removes
existing packages.

Mac App Store apps such as Xcode and KeepSolid VPN Unlimited are intentionally
outside nix-darwin activation because they require interactive App Store
sign-in and can block unattended `./update.sh` runs.

ProxyBridge is also installed manually. On Apple Silicon the Homebrew cask
requires Rosetta 2 for its `.pkg` installer, so it is not declared in the
Homebrew module. Reviewed non-secret defaults live at
`templates/proxybridge/ProxyBridge.defaults.json` and are copied to
`~/.config/proxybridge/`.

The two future Mac model services live as disabled templates under
`templates/launchagents/`. They are not copied or registered by Home Manager;
review the plists in the repository and install them manually when the model
paths, credentials, logs, and resource limits are ready for the Mini.

## Secrets boundary

Deployment secrets are SOPS-encrypted in `secrets/hosts/<deployment>.yaml`.
`secrets/manifest.nix` declares which hosts use SSH keys, which env secrets
they need, and how env keys map to runtime variable names. Bootstrap and render
automation lives in `scripts/bootstrap-secrets.sh` and
`scripts/render-deployment-env.sh`.

Nix-managed hosts decrypt secrets through `sops-nix` during Home Manager
activation (`modules/shared/secrets.nix`):

- SSH private keys → `~/.ssh/id_ed25519`
- Env secrets → `~/.config/dotfiles/secrets/env/<key>`

Synology and similar handoff targets render dotenv files at build time. Plaintext
never enters the Nix store or Docker image layers.

Bootstrap a deployment:

```sh
nix run .#bootstrap-secrets -- ssh baguette --github
nix run .#bootstrap-secrets -- env synology-dev tailscale_auth_key
./update.sh --target baguette
./update.sh --synology
```

Age private identities stay host-local at `~/.config/sops/age/keys.txt`. Public
age recipients are committed under `secrets/age-recipients/`. See
[`secrets/README.md`](../secrets/README.md) for the full schema.
