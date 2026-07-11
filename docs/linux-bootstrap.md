# Debian Linux host bootstrap

The `crostini` Home Manager output owns the user-facing Linux tools and the
reviewed X11/Wayland files. It does not pretend to manage a Docker daemon,
kernel drivers, host devices, or GUI installers. Those are installed once on
the outer Debian host and are intentionally absent from
`homeConfigurations.debianTrixie`.

The future Bruschetta host should use Debian Trixie repositories only. Do not
copy the old Bookworm Tabby repository from `install.sh` into a Trixie system.
Confirm the host before applying packages:

```sh
. /etc/os-release
test "$ID" = debian && test "${VERSION_CODENAME:-}" = trixie
```

## Native host packages

The following are the host boundary approved for Crostini/Bruschetta:

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
Sommelier/Weston service wiring likewise stays in the host layer.

Do not enable a launcher from Home Manager merely because a template exists:
the wrapper must be tested against the active Crostini/Bruschetta display
server, XKB path, and `WAYLAND_DISPLAY`/`DISPLAY` environment first.

## Evaluate without installing

```sh
nix flake check
nix build .#homeConfigurations.crostini.activationPackage
nix build .#homeConfigurations.debianTrixie.activationPackage
```

The Trixie container profile contains the same shared CLI/toolchain profile,
but leaves host Docker, GPU/device access, keyrings, desktop services, and GUI
applications outside the container. Opting into GUI packages requires an
explicit module override and a container image that supplies a display server.
