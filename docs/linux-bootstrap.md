# Crostini to Baguette Linux bootstrap

The active Linux machine is Crostini. The `crostini` Home Manager output owns
its user-facing Linux tools and reviewed X11/Wayland files. It does not pretend
to manage a Docker daemon,
kernel drivers, host devices, or GUI installers. Those are installed once on
the outer Debian host and are intentionally absent from
`homeConfigurations.debianTrixie`.

The future Baguette host should use Debian Trixie repositories only. Do not
copy an older Bookworm repository into a Trixie system. Validate the new host
before reusing any Crostini-specific integration.
Confirm the host before applying packages:

```sh
. /etc/os-release
test "$ID" = debian && test "${VERSION_CODENAME:-}" = trixie
```

## Native host packages

The following are the host boundary approved for Crostini and, after review,
Baguette:

- Docker CE: `docker-ce`, `docker-ce-cli`, `containerd.io`,
  `docker-buildx-plugin`, `docker-compose-plugin`
- Desktop/device integration: `gnome-keyring`, `libsecret-tools`, `adb`,
  `wl-clipboard`, `xclip`, `xdotool`, `x11-xkb-utils`, `fontconfig`
- Graphics/runtime support: `vulkan-tools`, `intel-gpu-tools`, VA-API/OpenCL
  runtime packages appropriate to the host GPU
- Archive and utility packages: `p7zip-full`, `unrar`, `streamlink`, and
  `qmk` (where the Debian package or a reviewed upstream install is available)

Docker must be installed from Docker's official Debian Trixie repository after
its signing key and `deb822` source have been reviewed. The profile does not
add repositories or run `apt`; this prevents a Home Manager activation from
silently changing host trust or daemon state.

GUI applications such as Zed, Tabby, Cursor, VS Code, VLC, and Chrome should
be installed through the approved Debian package, Flatpak, or vendor channel
for the host. Their launcher files are machine-local and are not overwritten
by this profile.

## Preserved Crostini integration

Home Manager publishes non-invasive templates for portable baselines:

- `~/.config/dotfiles/templates/Xresources` (120 DPI) and
  `~/.config/dotfiles/templates/weston.ini` (XWayland module)
- a Nerd Font fallback under the managed, uniquely named file
  `~/.config/fontconfig/conf.d/10-dotfiles-symbols.conf`
- the shared `finner`/Finansi keyboard intent, which remains an explicit host
  integration because XKB device names and Sommelier wiring differ by machine
- Sommelier/Weston and Finansi launch wrappers, which remain host-owned and
  should be enabled only after checking the current display/session variables

Keep machine-specific additions in `~/.Xresources.local` and host launchers in
`~/.local/share/applications`. Review the existing `~/.config/xkb/finner.xkb`
before promoting it to a shared file; it contains physical-key assumptions.
Sommelier/Weston service wiring likewise stays in the host layer. The current
host-owned set to preserve (disabled until manually tested) is:

- `~/.sommelierrc` and its `setxkbmap -layout finansi` hook
- `~/.config/systemd/user/finner-x11-keymap.service`
- `~/.local/bin/zed-crostini-x11` and other local launch wrappers

These files may be imported into a future Baguette host module only after their
`DISPLAY`, `WAYLAND_DISPLAY`, Sommelier socket, and XKB paths are parameterized.

Do not enable a launcher from Home Manager merely because a template exists:
the wrapper must be tested against the active Crostini display first, then
against the Baguette display server, XKB path, and
`WAYLAND_DISPLAY`/`DISPLAY` environment.

## Evaluate without installing

```sh
nix flake check
nix build .#homeConfigurations.crostini.activationPackage
nix build .#homeConfigurations.baguette.activationPackage
nix build .#homeConfigurations.debianTrixie.activationPackage
```

The Trixie container profile mirrors the complete shared CLI/toolchain profile
(including `rg`, `fd`, `fzf`, `zoxide`, Git/GitHub tooling, Rust/Go/Zig, Node,
Python/uv, and shell tooling), but leaves host Docker, GPU/device access,
keyrings, desktop services, and GUI applications outside the container.

Fast-moving Node-based CLIs are intentionally not built by Nix. After
activating the profile, download their published npm packages into the
user-owned `~/.local` prefix:

```sh
install-node-tools
# Or include the agent-browser managed browser download:
install-node-tools --with-browser
```

The approved GUI set is Zed, Tabby, Sublime Text, Cursor, VS Code, VLC, and
Google Chrome. `dotfiles.container.allowGuiPackages` remains `false` and
`guiPackages` defaults to an empty list in the flake output. A display-enabled
image must opt in explicitly, for example:

```nix
{
  dotfiles.container.allowGuiPackages = true;
  dotfiles.container.guiPackages = [ pkgs.zed-editor pkgs.vlc ];
}
```

This opt-in does not provide a display server or host device access; those
remain image/runtime responsibilities.
