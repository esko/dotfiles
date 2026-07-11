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
in
{
  imports = [ ./ssh.nix ];

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
  };

  config = {
    home.packages = lib.optionals config.dotfiles.linux.enableHostTools (optionalPackages [
      # Approved Linux-only tools and runtime integration.
      "android-tools" "adb" "jdk17" "openjdk17" "vulkan-tools"
      "libva-utils" "intel-gpu-tools" "intel-media-driver" "mesa"
      "libdrm" "clinfo" "ocl-icd" "onevpl-intel-gpu"
      "wl-clipboard" "xclip" "xdotool" "xkbcomp" "xkeyboard-config"
      "fontconfig" "gnome-keyring" "libsecret" "libsecret-tools"
      "p7zip" "unrar" "streamlink" "qmk" "litert-lm"
    ]);

    # Keep templates separate from active host files. Home Manager must not
    # replace an existing Crostini/Sommelier launcher or display configuration.
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
      if [ "${hostName}" = "crostini" ] && [ "${lib.boolToString config.dotfiles.linux.nativeBootstrap}" = true ]; then
        $DRY_RUN_CMD printf '%s\\n' "Linux host integration: see docs/linux-bootstrap.md"
      fi
    '';
  };
}
