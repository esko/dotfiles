{ config, lib, pkgs, username, homeDirectory, stateVersion, hostName, ... }:

let
  inherit (lib) mkIf mkOption types;

  # Linux package names move occasionally between nixpkgs channels. Optional
  # lookup keeps the profile evaluable while the Debian bootstrap remains the
  # authoritative path for daemon, driver, and device packages.
  optionalPackages = names:
    builtins.concatLists (map
      (name: lib.optional (builtins.hasAttr name pkgs) (builtins.getAttr name pkgs))
      names);

  cursorPackage = if builtins.hasAttr "code-cursor" pkgs then pkgs.code-cursor else null;
  antigravityPackage = if builtins.hasAttr "antigravity" pkgs then pkgs.antigravity else null;
in
{
  options.dotfiles.linux = {
    enableHostTools = mkOption {
      type = types.bool;
      default = true;
      description = "Install Linux workstation CLI and graphics diagnostics in Home Manager.";
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
      description = "Install Cursor and Antigravity GUI editors from nixpkgs.";
    };
  };

  config = {
    home.packages =
      lib.optionals config.dotfiles.linux.enableHostTools (optionalPackages [
      # Approved Linux-only tools and runtime integration.
      "android-tools" "adb" "jdk17" "openjdk17" "vulkan-tools"
      "libva-utils" "intel-gpu-tools" "intel-media-driver" "mesa"
      "libdrm" "clinfo" "ocl-icd" "vpl-gpu-rt" "nettools" "traceroute"
      "wl-clipboard" "xclip" "xdotool" "xkbcomp" "xkeyboard-config"
      "fontconfig" "gnome-keyring" "libsecret" "libsecret-tools"
      "p7zip" "unrar" "streamlink" "qmk" "litert-lm"
    ]) ++ lib.optionals config.dotfiles.linux.enableGuiApps (optionalPackages [
      "code-cursor"
      "antigravity"
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

    # System Manager builds users.users.<name>.packages into
    # /etc/profiles/per-user/<name>, but unlike NixOS it does not currently add
    # that profile to login PATH. Baguette also keeps Determinate Nix host-owned,
    # so expose its stable multi-user profile explicitly before shell hooks run.
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

    home.activation.dotfilesLinuxNotice = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ "${lib.boolToString (hostName == "baguette")}" = true ] && [ "${lib.boolToString config.dotfiles.linux.nativeBootstrap}" = true ]; then
        $DRY_RUN_CMD printf '%s\\n' "Linux host integration: see docs/linux-bootstrap.md"
      fi
    '';
  };
}
