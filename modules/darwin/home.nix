{
  config,
  lib,
  username,
  ...
}:

let
  zshSessionPath = lib.concatMapStringsSep "\n" (
    entry: ''      "${lib.escape [ "\\" "\"" "`" ] entry}"''
  ) config.home.sessionPath;
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
      force = config.dotfiles.stowMigration.forceLegacyCollisions;
    };
    home.file.".config/proxybridge/README.md" = {
      source = ../../templates/proxybridge/README.md;
      force = config.dotfiles.stowMigration.forceLegacyCollisions;
    };

    # nix-darwin exposes Home Manager packages under /etc/profiles/per-user.
    # Add the profile explicitly so node/npm are available before shell hooks run.
    # Homebrew belongs here too: remote mosh/ssh run a non-login shell that
    # sources hm-session-vars (.zshenv) but not .zprofile (brew shellenv), so
    # brew-only tools like mosh-server / et / tsshd were invisible to mosh.
    # Keep macOS admin paths explicit as well: tools such as sysctl and
    # system_profiler live under /usr/sbin and are used by hardware probes.
    home.sessionPath = [
      "/opt/homebrew/bin"
      "/opt/homebrew/sbin"
      "/usr/sbin"
      "/sbin"
      "/etc/profiles/per-user/${username}/bin"
      "/nix/var/nix/profiles/default/bin"
    ];

    # The pinned Home Manager revision sources home.sessionPath from .zshenv.
    # On macOS login shells, /etc/zprofile runs path_helper afterwards and can
    # rebuild PATH, dropping entries such as $HOME/.local/bin. Reapply the final
    # merged Home Manager path list from the user .zprofile, matching the newer
    # upstream Home Manager behavior while keeping this deployment pin stable.
    programs.zsh.profileExtra = lib.mkAfter ''
      typeset -U path
      path=(
${zshSessionPath}
        $path
      )
      export PATH
    '';
  };
}
