# Baguette Linux bootstrap

Baguette is a native Debian Trixie host managed by System Manager with Home
Manager embedded for `esko`.

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
repositories. Home Manager may still ship Nix copies of some diagnostics (for
example `vulkan-tools`); prefer the Debian package for anything that must
integrate with the host display, keyring, or device stack:

- base integration: `openssh-client`, `ca-certificates`, `curl`, `git`, `zsh`
- Docker host: `docker-ce`, `docker-ce-cli`, `containerd.io`,
  `docker-buildx-plugin`, `docker-compose-plugin`
- desktop/device integration (apt-owned; not reinstalled by Home Manager):
  `gnome-keyring`, `libsecret-tools`, `adb`, `wl-clipboard`, `xclip`,
  `xdotool`, `x11-xkb-utils`, `fontconfig`
- graphics/runtime support: `vulkan-tools`, `intel-gpu-tools`, and appropriate
  VA-API/OpenCL packages
- optional utilities: `unrar`, `streamlink`, and `qmk` (also available via Nix
  when useful offline from apt)
- VPN mesh: `tailscale` from Tailscale's Debian repository for `tailscaled`

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

## SSH keys (Baguette ↔ Mini)

Home Manager only writes `~/.ssh/id_ed25519` after SOPS SSH material exists.
If `~/.ssh` is empty, bootstrap on each host (creates age identity + keypair),
commit the public key and encrypted host secret, then activate both sides:

```sh
# On Baguette
cd ~/dotfiles
./update.sh --target baguette --bootstrap-secrets --github
# Review + commit secrets/public/baguette-id_ed25519.pub and secrets/hosts/baguette.yaml

# On Mini
cd ~/dotfiles && git pull --ff-only
./update.sh --target mini --bootstrap-secrets --github
# Commit secrets/public/mini-id_ed25519.pub and secrets/hosts/mini.yaml

# Activate again on both hosts so authorized_keys + peer Host blocks apply
./update.sh
```

After both public keys are committed, Mini's `authorized_keys` includes
Baguette, and Baguette gets `Host mini macmini …` using `IdentityFile
~/.ssh/id_ed25519`. Then `ssh mini` should not ask for a password.

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

## Numtide binary cache

Baguette follows [`llm-agents.nix`](https://github.com/numtide/llm-agents.nix),
which publishes pre-built agent CLIs to `https://cache.numtide.com`. The flake
declares that cache in `nixConfig`.

Determinate Nix owns `/etc/nix/nix.conf` and regenerates it. Custom caches must
go in `/etc/nix/nix.custom.conf` (loaded via `!include`). Editing `nix.conf`
directly does not stick. On Baguette, run the host helper once (safe to re-run):

```sh
./scripts/enable-numtide-cache.sh
```

That writes these lines to `/etc/nix/nix.custom.conf`, restarts the daemon, and
verifies they appear in `nix config show`:

```
extra-substituters = https://cache.numtide.com
extra-trusted-substituters = https://cache.numtide.com
extra-trusted-public-keys = niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=
```

`trusted-substituters` matters because Determinate typically sets
`trusted-users = root` only; without it, unprivileged builds ignore the cache
and print `ignoring the client-specified setting 'trusted-public-keys'`.

## Build before activation

From the repository checkout:

```sh
nix flake lock
nix flake check
./update.sh --check-only
```

`--check-only` builds the baguette closure with the Numtide cache options and
does not mutate `/etc`, users, or services. Review the branch diff and build
result before switching.

## Activate Baguette

Prefer the day-to-day entry point, which enables the Numtide cache and avoids a
redundant pre-activation build:

```sh
./update.sh --target baguette
```

Or activate with `./update.sh` after the custom.conf helper has run (preferred).
Direct `nix run` of system-manager only helps if Numtide is already trusted in
`nix.custom.conf`; client `--option trusted-public-keys` is ignored for
non-trusted users.

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

Baguette also installs Cursor and Antigravity from nixpkgs, plus a pinned
Inkscape **1.5 development** AppImage (`packages/inkscape-beta.nix`) because
nixpkgs still ships 1.4.x. Launch them from the application menu or with the
`cursor`, `antigravity`, and `inkscape` commands after activation. Desktop
entries (Inkscape as “Inkscape 1.5 Beta”) are published under
`~/.local/share/applications/` so ChromeOS and other XDG launchers can find
them.

## Display integration templates

Home Manager publishes non-invasive templates for optional display integration:

- `~/.config/dotfiles/templates/Xresources`
- `~/.config/dotfiles/templates/weston.ini`
- `~/.config/dotfiles/templates/finner.xkb`
- Nerd Font fallback configuration

Live Sommelier, XKB, display, and launcher files remain host-owned until their
paths and device assumptions are parameterized and tested. Do not activate
those templates merely because they are present.
