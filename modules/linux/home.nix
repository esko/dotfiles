{ config, lib, pkgs, username, homeDirectory, stateVersion, hostName, ... }:

let
  inherit (lib) mkIf mkOption types;
  inherit (import ../lib/optional-packages.nix { inherit lib; }) optionalPackages;

  cursorPackage = if builtins.hasAttr "code-cursor" pkgs then pkgs.code-cursor else null;
  antigravityPackage = if builtins.hasAttr "antigravity" pkgs then pkgs.antigravity else null;
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
      description = "Install Linux GUI apps from nixpkgs (Cursor, Antigravity, Inkscape).";
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
    ]) ++ lib.optionals config.dotfiles.linux.enableGuiApps (optionalPackages pkgs [
      "code-cursor"
      "antigravity"
      "inkscape"
    ]);

    xdg.enable = mkIf config.dotfiles.linux.enableGuiApps true;

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
