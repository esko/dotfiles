{ config, lib, pkgs, username, homeDirectory, stateVersion, hostName
, inkscapeBeta ? null, ... }:

let
  inherit (lib) mkIf mkOption types;
  inherit (import ../lib/optional-packages.nix { inherit lib; }) optionalPackages;

  cursorPackage = if builtins.hasAttr "code-cursor" pkgs then pkgs.code-cursor else null;
  antigravityPackage = if builtins.hasAttr "antigravity" pkgs then pkgs.antigravity else null;
  # Stable 1.4.x from nixpkgs; optional pinned 1.5-dev AppImage beside it.
  inkscapeStable =
    if builtins.hasAttr "inkscape" pkgs then pkgs.inkscape else null;
  inkscapeDev = inkscapeBeta;
in
{
  options.dotfiles.linux = {
    enableHostTools = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Install Linux workstation diagnostics and Nix-owned utilities in Home
        Manager. Daemon/keyring/clipboard packages remain apt-owned on Baguette
        (see docs/linux-bootstrap.md); this list is the Nix supplement, not a
        second copy of the Debian integration set.
      '';
    };

    enableDesktopConfigs = mkOption {
      type = types.bool;
      default = true;
      description = "Install the reviewed X11/Wayland integration configuration files.";
    };

    nativeBootstrap = mkOption {
      type = types.bool;
      default = true;
      description = "Document native Debian packages and services required outside Home Manager.";
    };

    enableGuiApps = mkOption {
      type = types.bool;
      default = hostName == "baguette";
      description = "Install Linux GUI apps (Cursor, Antigravity, Inkscape 1.4 + 1.5-dev).";
    };
  };

  config = {
    home.packages =
      lib.optionals config.dotfiles.linux.enableHostTools (optionalPackages pkgs [
      # Nix-owned Linux workstation tools. Prefer Debian packages listed in
      # docs/linux-bootstrap.md for keyring, clipboard, and device daemons.
      "android-tools" "jdk17" "vulkan-tools"
      "libva-utils" "intel-gpu-tools" "intel-media-driver" "mesa"
      "libdrm" "clinfo" "ocl-icd" "vpl-gpu-rt" "nettools" "traceroute"
      "xkbcomp" "xkeyboard-config"
      "unrar" "streamlink" "qmk" "litert-lm"
    ]) ++ lib.optionals config.dotfiles.linux.enableGuiApps (
      (optionalPackages pkgs [
        "code-cursor"
        "antigravity"
      ])
      ++ lib.optional (inkscapeStable != null) inkscapeStable
      ++ lib.optional (inkscapeDev != null) inkscapeDev
    );

    xdg.enable = mkIf config.dotfiles.linux.enableGuiApps true;

    # ChromeOS Crostini's cros-garcon defaults to /usr/{local,}share only for
    # XDG_DATA_DIRS (plus ~/.local/share when HOME is set). useUserPackages puts
    # Nix .desktop files under /etc/profiles/per-user/<user>/share, which garcon
    # never sees unless we extend the service. Also widen PATH so TryExec=name
    # entries from nixpkgs resolve. See wiki.nixos.org/wiki/Installing_Nix_on_Crostini.
    xdg.configFile = mkIf (hostName == "baguette" && config.dotfiles.linux.enableGuiApps) {
      "systemd/user/cros-garcon.service.d/override.conf".text = ''
        [Service]
        Environment="PATH=%h/.local/bin:/etc/profiles/per-user/${username}/bin:%h/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/local/games:/usr/sbin:/usr/bin:/usr/games:/sbin:/bin"
        Environment="XDG_DATA_DIRS=/etc/profiles/per-user/${username}/share:%h/.nix-profile/share:%h/.local/share:%h/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share"
      '';
    };

    # Do not set home.sessionVariables.XDG_DATA_DIRS here: replacing the session
    # value can break Crostini/GTK terminals. Garcon gets its paths from the
    # systemd drop-in above; shells already see HM/profile shares via PATH.

    home.activation.publishBaguetteDesktopEntries =
      mkIf (hostName == "baguette" && config.dotfiles.linux.enableGuiApps)
        (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          # Prefer the repo helper when present (writes /usr/local + ~/.local and
          # restarts garcon). Fall back to a minimal local materialize otherwise.
          if [ -x "${homeDirectory}/dotfiles/scripts/publish-crostini-apps.sh" ]; then
            $DRY_RUN_CMD "${homeDirectory}/dotfiles/scripts/publish-crostini-apps.sh" || true
          elif [ -x "$HOME/dotfiles/scripts/publish-crostini-apps.sh" ]; then
            $DRY_RUN_CMD "$HOME/dotfiles/scripts/publish-crostini-apps.sh" || true
          else
            apps_dir="${homeDirectory}/.local/share/applications"
            $DRY_RUN_CMD mkdir -p "$apps_dir"
            for desktop in cursor.desktop antigravity.desktop inkscape.desktop inkscape-beta.desktop; do
              if [ -e "$apps_dir/$desktop" ] && [ -L "$apps_dir/$desktop" ]; then
                $DRY_RUN_CMD cp -fL "$apps_dir/$desktop" "$apps_dir/$desktop.real"
                $DRY_RUN_CMD mv -f "$apps_dir/$desktop.real" "$apps_dir/$desktop"
              fi
            done
            if command -v systemctl >/dev/null 2>&1; then
              $DRY_RUN_CMD systemctl --user daemon-reload || true
              $DRY_RUN_CMD systemctl --user restart cros-garcon.service || true
            fi
          fi
        '');

    xdg.desktopEntries = mkIf config.dotfiles.linux.enableGuiApps (
      lib.optionalAttrs (cursorPackage != null) {
        cursor = {
          name = "Cursor";
          genericName = "Text Editor";
          comment = "AI-powered code editor";
          exec = "${lib.getExe cursorPackage} %F";
          icon = "cursor";
          terminal = false;
          categories = [ "Development" "TextEditor" ];
          mimeType = [
            "application/x-cursor-workspace"
            "inode/directory"
            "text/plain"
          ];
          startupNotify = true;
        };
      }
      // lib.optionalAttrs (antigravityPackage != null) {
        antigravity = {
          name = "Antigravity";
          genericName = "IDE";
          comment = "Agentic development platform";
          exec = "${lib.getExe antigravityPackage} %F";
          icon = "antigravity";
          terminal = false;
          categories = [ "Development" "IDE" ];
          startupNotify = true;
        };
      }
      // lib.optionalAttrs (inkscapeStable != null) {
        inkscape = {
          name = "Inkscape";
          genericName = "Vector Graphics Editor";
          comment = "Inkscape ${inkscapeStable.version or "1.4"} (stable)";
          exec = "${lib.getExe inkscapeStable} %F";
          icon = "inkscape";
          terminal = false;
          categories = [ "Graphics" "VectorGraphics" "2DGraphics" ];
          mimeType = [
            "image/svg+xml"
            "image/svg+xml-compressed"
            "application/vnd.corel-draw"
            "application/pdf"
            "image/png"
            "image/jpeg"
          ];
          startupNotify = true;
        };
      }
      // lib.optionalAttrs (inkscapeDev != null) {
        inkscape-beta = {
          name = "Inkscape 1.5 Beta";
          genericName = "Vector Graphics Editor";
          comment = "Inkscape 1.5 development AppImage";
          exec = "${lib.getExe inkscapeDev} %F";
          icon = "inkscape";
          terminal = false;
          categories = [ "Graphics" "VectorGraphics" "2DGraphics" ];
          mimeType = [
            "image/svg+xml"
            "image/svg+xml-compressed"
            "application/vnd.corel-draw"
            "application/pdf"
            "image/png"
            "image/jpeg"
          ];
          startupNotify = true;
        };
      }
    );

    # Home Manager useUserPackages installs into /etc/profiles/per-user/<name>.
    # System Manager does not put that path on login PATH the way NixOS does.
    # Determinate Nix owns /nix/var/nix/profiles/default; expose both explicitly.
    home.sessionPath = lib.optionals (hostName == "baguette") [
      "/nix/var/nix/profiles/default/bin"
      "/etc/profiles/per-user/${username}/bin"
    ];

    # Keep templates separate from active host files. Home Manager must not
    # replace an existing Baguette display configuration.
    home.file = mkIf config.dotfiles.linux.enableDesktopConfigs {
      ".config/dotfiles/templates/Xresources" = {
        text = ''
          ! Template only; merge with the host's ~/.Xresources.
          Xft.dpi: 120
        '';
      };

      ".config/dotfiles/templates/weston.ini" = {
        text = ''
          # Template only; preserve host-specific Sommelier settings.
          [core]
          modules=xwayland.so
        '';
      };

      ".config/dotfiles/templates/finner.xkb" = {
        text = ''
          // Template placeholder. Keep the live physical-key map in
          // ~/.config/xkb/finner.xkb until it has been reviewed for sharing.
        '';
      };

      ".config/fontconfig/conf.d/10-dotfiles-symbols.conf" = {
        text = ''
          <?xml version="1.0"?>
          <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
          <fontconfig>
            <!-- Keep Nerd Font glyph fallback for terminal/editor fonts. -->
            <alias>
              <family>monospace</family>
              <prefer><family>Symbols Nerd Font</family></prefer>
            </alias>
          </fontconfig>
        '';
      };
    };

  };
}
