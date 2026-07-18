{ config, lib, pkgs, username, homeDirectory, stateVersion, hostName, ... }:

let
  cfg = config.dotfiles.darwin;
in
{
  options.dotfiles.darwin = {
    proxyBridgePackage = lib.mkOption {
      type = lib.types.str;
      default = "proxybridge (manual Homebrew cask; Rosetta required on Apple Silicon)";
      description = "ProxyBridge install path; not managed during nix-darwin activation.";
    };

    ssh = {
      configInclude = lib.mkOption {
        type = lib.types.str;
        default = "Include ~/.ssh/config.d/*.conf";
        description = "Include declaration to add to the user's main SSH config.";
      };
    };
  };

  config = {
    # Peer SSH Host blocks come from modules/shared/secrets.nix once SOPS
    # identities exist under secrets/public/.

    home.file.".config/proxybridge/ProxyBridge.defaults.json" = {
      source = ../../templates/proxybridge/ProxyBridge.defaults.json;
      force = true;
    };
    home.file.".config/proxybridge/README.md" = {
      source = ../../templates/proxybridge/README.md;
      force = true;
    };

    # nix-darwin exposes Home Manager packages under /etc/profiles/per-user.
    # Add the profile explicitly so node/npm are available before shell hooks run.
    # Homebrew belongs here too: remote mosh/ssh run a non-login shell that
    # sources hm-session-vars (.zshenv) but not .zprofile (brew shellenv), so
    # brew-only tools like mosh-server / et / tsshd were invisible to mosh.
    home.sessionPath = [
      "/opt/homebrew/bin"
      "/opt/homebrew/sbin"
      "/etc/profiles/per-user/${username}/bin"
      "/nix/var/nix/profiles/default/bin"
    ];
  };
}

