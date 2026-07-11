{ config, lib, pkgs, username, homeDirectory, stateVersion, hostName, ... }:

let
  inherit (lib) mkIf mkOption types;

  optionalPackages = names:
    builtins.concatLists (map
      (name: lib.optional (builtins.hasAttr name pkgs) (builtins.getAttr name pkgs))
      names);
in
{
  options.dotfiles.container = {
    enableSharedTools = mkOption {
      type = types.bool;
      default = true;
      description = "Install the shared headless CLI profile in Debian Trixie containers.";
    };

    allowGuiPackages = mkOption {
      type = types.bool;
      default = false;
      description = "Opt into GUI packages explicitly; disabled for headless containers.";
    };

    guiPackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "Explicit GUI packages for a container image that provides a display server.";
    };
  };

  config = {
    # Shared Home Manager already supplies the approved CLI/toolchain set.
    # Keep only container-safe additions here; Docker, drivers, keyrings,
    # desktop services, and device access belong to the outer Debian host.
    home.packages = lib.optionals config.dotfiles.container.enableSharedTools (optionalPackages [
      "ca-certificates" "procps" "which"
    ]) ++ lib.optionals config.dotfiles.container.allowGuiPackages config.dotfiles.container.guiPackages;

    # GUI packages are intentionally opt-in and empty by default. This option
    # exists to make the headless limitation explicit without pulling desktop
    # dependencies into every Debian Trixie image.
    home.activation.dotfilesContainerNotice = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD printf '%s\\n' "Debian Trixie container profile: host services/devices/GUI remain outside Home Manager"
    '';
  };
}
