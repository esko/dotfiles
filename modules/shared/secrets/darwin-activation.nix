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

        # setupLaunchAgents may already have started the agent. Stop it fully
        # before the synchronous install so two writers cannot update the same
        # secrets generation concurrently.
        /bin/launchctl bootout --wait "$domain_target/org.nix-community.home.sops-nix" 2>/dev/null || true

        if [[ -z "$installer" || ! -x "$installer" ]]; then
          printf '%s\n' "sops-nix: secret installer is not executable: ''${installer:-<unset>}" >&2
          exit 1
        fi

        # launchd's deliberately minimal environment must apply only to the
        # secret installer. Exporting it in the parent activation shell removes
        # Home Manager's Nix paths and makes later helpers such as gettext vanish.
        activation_path="$PATH"
        (
          ${installerEnvironmentExports}
          # sops-install-secrets resolves %r with `getconf DARWIN_USER_TEMP_DIR`.
          # Preserve the Home Manager activation PATH while also applying the
          # launch-agent PATH and guaranteeing native macOS tools are available.
          export PATH="$activation_path''${PATH:+:$PATH}:/usr/bin:/bin:/usr/sbin:/sbin"
          "$installer"
        )

        # RunAtLoad starts the agent during bootstrap; no separate kickstart is
        # needed and avoiding it prevents a second immediate secret installation.
        if [[ -f "$plist" ]]; then
          /bin/launchctl bootstrap "$domain_target" "$plist" 2>/dev/null || true
        fi
      ''
    );
  };
}
