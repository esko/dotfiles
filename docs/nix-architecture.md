# Nix architecture

The flake separates portable user configuration from host integration:

- `homeConfigurations.crostini` is a standalone Home Manager profile for the
  current Crostini host.
- `homeConfigurations.baguette` is the containerless/native Debian Trixie host
  profile for the future Baguette migration. It intentionally uses the Linux
  host module, not the headless container module.
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

Nix is not installed by Home Manager. On a machine with Nix enabled, first
create and review the lock file:

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
the foundation. The Darwin Home Manager module now exposes an opt-in
`dotfiles.darwin.ssh` interface: enable it only after adding a real per-host
Ed25519 secret (for example `ssh/mini/id_ed25519`) encrypted with the Mini's
age recipient. The module writes the decrypted key to `~/.ssh/id_ed25519` at
activation and never creates a key or fake encrypted payload itself. Public-key
text and an SSH config fragment are separate declarations. Management of
`~/.ssh/authorized_keys` is disabled by default and requires an explicit,
non-empty `authorizedKeys` list; it is intentionally not inferred from the
private key. The generated `~/.ssh/config.d/90-dotfiles-mini.conf` is inert
until the existing `~/.ssh/config` contains `Include ~/.ssh/config.d/*.conf`;
the module leaves that hand-maintained file untouched.

Bootstrap the secret boundary manually on each host:

1. Install `age`/`sops` and configure the host age recipient in `.sops.yaml`.
2. Add only the encrypted secret under `secrets/`; keep recovery keys and
   plaintext exports outside the repository.
3. Set `dotfiles.darwin.ssh.enable = true` in a private host overlay and run a
   reviewed `darwin-rebuild build` before `switch`.
4. Add `authorizedKeys` only when incoming SSH access is intentionally part of
   that host's role.
