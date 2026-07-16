{ config, lib, pkgs, username, homeDirectory, stateVersion, hostName, ... }:

let
  inherit (lib) mkIf mkOption types;
  inherit (import ../lib/optional-packages.nix { inherit lib; }) optionalPackages;
in
{
  options.dotfiles.container = {
    enableSharedTools = mkOption {
      type = types.bool;
      default = true;
      description = "Install the shared headless CLI profile in container images.";
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
    # Containers cannot assume a host-provided SSH client, so keep Nix OpenSSH
    # here. Native Debian and macOS profiles use their system clients instead.
    home.packages = lib.optionals config.dotfiles.container.enableSharedTools (optionalPackages pkgs [
      "ca-certificates" "openssh" "procps" "which"
    ]) ++ lib.optionals config.dotfiles.container.allowGuiPackages config.dotfiles.container.guiPackages;
  };
}
