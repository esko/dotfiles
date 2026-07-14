# Crostini to Baguette Linux bootstrap

Crostini remains a standalone Home Manager target. Baguette is a native Debian
Trixie host managed by System Manager with Home Manager embedded for `esko`.
The distinction is intentional: Crostini is an environment supplied by
ChromeOS, while Baguette owns its Debian users and services.

## Confirm the Baguette host

Baguette must be Debian Trixie on x86_64:

```sh
. /etc/os-release
test "$ID" = debian
test "${VERSION_CODENAME:-}" = trixie
test "$(uname -m)" = x86_64
```

The pinned post-1.1 System Manager revision still does not include Debian in its
runtime allow-list, so the profile explicitly enables the documented
`allowAnyDistro` escape hatch. Repository preflight checks compensate by
verifying the exact Baguette account, distro, architecture, and shell
assumptions before activation.

The revision is newer than v1.1.0 because Home Manager 26.11 on Linux requires
System Manager's `system.userActivationScripts` compatibility stub. Keep the
activation CLI on the same pinned revision as `flake.nix`.

## Native Debian packages

System Manager does not replace apt, the kernel, drivers, or the display stack.
Install and maintain the host-owned packages through reviewed Debian/vendor
repositories:

- base integration: `openssh-client`, `ca-certificates`, `curl`, `git`, `zsh`
- Docker host: `docker-ce`, `docker-ce-cli`, `containerd.io`,
  `docker-buildx-plugin`, `docker-compose-plugin`
- desktop/device integration: `gnome-keyring`, `libsecret-tools`, `adb`,
  `wl-clipboard`, `xclip`, `xdotool`, `x11-xkb-utils`, `fontconfig`
- graphics/runtime support: `vulkan-tools`, `intel-gpu-tools`, and appropriate
  VA-API/OpenCL packages
- optional utilities not suitable for the shared Nix profile: `unrar`,
  `streamlink`, and `qmk`
- VPN mesh: `tailscale` from Tailscale's Debian repository

Use Debian's OpenSSH client. A second Nix OpenSSH build can read Debian's
`/etc/ssh/ssh_config` with a different compiled feature set, producing warnings
for options such as `GSSAPIAuthentication`.

At minimum, prepare the shell and verify the existing account:

```sh
sudo apt update
sudo apt install -y zsh

test -x /usr/bin/zsh
grep -qxF /usr/bin/zsh /etc/shells
id esko
test "$(id -u esko)" = 1000
test "$(id -g esko)" = 1000
test "$(getent passwd esko | cut -d: -f6)" = /home/esko
```

Do not run `chsh` manually after this migration. System Manager declares the
login shell and updates the existing mutable account during activation.
Passwords are not declared.

GitHub uses HTTPS as the bootstrap-safe default. Authenticate with
`gh auth login`; change an individual remote to SSH only after that host has an
SSH key enrolled with GitHub.

Install Tailscale for the host daemon and systemd integration:

```sh
curl -fsSL https://pkgs.tailscale.com/stable/debian/$(. /etc/os-release && printf '%s' "${VERSION_CODENAME}")/noarmor.gpg \
  | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL "https://pkgs.tailscale.com/stable/debian/$(. /etc/os-release && printf '%s' "${VERSION_CODENAME}").tailscale-keyring.list" \
  | sudo tee /etc/apt/sources.list.d/tailscale.list
sudo apt update
sudo apt install -y tailscale
sudo systemctl enable --now tailscaled
```

The shared Home Manager profile also installs the Nix `tailscale` CLI. Use the
Debian package for `tailscaled` on native Linux hosts.

## Build before activation

From the repository checkout:

```sh
nix flake lock
nix flake check
nix build .#systemConfigs.baguette
```

Building does not mutate `/etc`, users, or services. Review the branch diff and
build result before switching.

## Activate Baguette

```sh
nix run github:numtide/system-manager/96f724be6f1411286e8ad0202e3e624c10116a6d -- \
  switch --flake "$PWD#baguette" --sudo
```

One System Manager activation now:

- verifies the existing `esko` UID, GID, home, and Debian Zsh installation
- keeps users mutable and retains `esko` in the Debian `sudo` group
- changes the account shell to `/usr/bin/zsh`
- activates the embedded Home Manager configuration
- generates `.zshrc`, Starship, aliases, completions, and user packages

Log out completely and log back in after the first activation. Confirm:

```zsh
printf 'argv0=%s\nSHELL=%s\n' "$0" "$SHELL"
getent passwd esko | cut -d: -f7
readlink -f ~/.zshrc
command -v starship
```

Expected login shell values are `/usr/bin/zsh` and `-zsh`. The Home Manager
`.zshrc` should resolve into the Nix store and contain a real Starship init path.

## Node-based CLI bootstrap

Fast-moving Node CLIs are not built by Nix. After Home Manager activation, use
the explicit user-owned npm installer. It requires the active `node` runtime to
be Node.js 24 or newer:

```sh
install-node-tools
# Or include the agent-browser managed browser download:
install-node-tools --with-browser
```

The npm prefix is `~/.local`, which is already on the managed PATH.

## Container profiles

There are two distinct Debian Trixie container outputs.

### Lightweight OCI/dev containers

Use this for normal Docker, Podman, and devcontainer images without systemd:

```sh
nix build .#homeConfigurations.debianTrixie.activationPackage
home-manager switch --flake .#debianTrixie
```

This profile owns only `/home/esko` files and user packages. It does not require
root, modify `/etc/passwd`, or install services.

### Machine-like systemd containers

Use this only for a privileged container that intentionally boots systemd as
PID 1 and owns its users and services:

```sh
nix build .#systemConfigs.debianTrixieContainer
nix run github:numtide/system-manager/96f724be6f1411286e8ad0202e3e624c10116a6d -- \
  switch --flake "$PWD#debianTrixieContainer" --sudo
```

A pre-activation assertion rejects this target unless PID 1 is systemd. This is
not the default for Synology Container Manager or ordinary OCI containers; use
the lightweight profile unless the image/runtime was deliberately built for
systemd and granted the required cgroup and privilege access.

## Preserved Crostini integration

Home Manager continues to publish non-invasive templates for Crostini:

- `~/.config/dotfiles/templates/Xresources`
- `~/.config/dotfiles/templates/weston.ini`
- `~/.config/dotfiles/templates/finner.xkb`
- Nerd Font fallback configuration

Live Sommelier, XKB, display, and launcher files remain host-owned until their
paths and device assumptions are parameterized and tested. Do not activate
those templates merely because they are present.
