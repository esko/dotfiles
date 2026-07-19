{
  config,
  lib,
  pkgs,
  homeDirectory,
  username,
  ...
}:

let
  cfg = config.dotfiles.secrets;
  sopsAgentConfig = config.launchd.agents."sops-nix".config;
  installer = sopsAgentConfig.Program or null;
  installerPath = if installer == null then "" else toString installer;
  installerEnvironment = sopsAgentConfig.EnvironmentVariables or { };
  installerEnvironmentExports = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: value: "export ${lib.escapeShellArg "${name}=${toString value}"}"
    ) installerEnvironment
  );
in
{
  # Workaround Mic92/sops-nix#910: stock Darwin activation races ahead of
  # setupLaunchAgents, so install secrets synchronously after linking the plist.
  # Use the original declarative launchd Program and EnvironmentVariables rather
  # than parsing Home Manager's generated plist, whose command is rewritten
  # through /bin/wait4path. Secret-installation failures propagate; only the
  # launchctl reload is best-effort.
  config = lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isDarwin) {
    assertions = [
      {
        assertion = installer != null;
        message = "sops-nix Darwin launch agent must define a Program";
      }
    ];

    home.activation.sops-nix = lib.mkForce (
      lib.hm.dag.entryAfter [ "setupLaunchAgents" ] ''
        domain_target="gui/$(/usr/bin/id -u ${lib.escapeShellArg username})"
        plist=${lib.escapeShellArg "${homeDirectory}/Library/LaunchAgents/org.nix-community.home.sops-nix.plist"}
        installer=${lib.escapeShellArg installerPath}

        /bin/launchctl bootout "$domain_target/org.nix-community.home.sops-nix" 2>/dev/null || true

        if [[ -z "$installer" || ! -x "$installer" ]]; then
          printf '%s\n' "sops-nix: secret installer is not executable: ''${installer:-<unset>}" >&2
          exit 1
        fi

        ${installerEnvironmentExports}
        # sops-install-secrets resolves %r with `getconf DARWIN_USER_TEMP_DIR`.
        # Keep the launchd PATH and guarantee the native macOS tools are visible
        # when this command is run synchronously from nix-darwin activation.
        export PATH="''${PATH:+$PATH:}/usr/bin:/bin:/usr/sbin:/sbin"
        "$installer"

        if [[ -f "$plist" ]]; then
          /bin/launchctl bootstrap "$domain_target" "$plist" 2>/dev/null || true
          /bin/launchctl kickstart -k "$domain_target/org.nix-community.home.sops-nix" 2>/dev/null || true
        fi
      ''
    );
  };
}
