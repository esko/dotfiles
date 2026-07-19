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
in
{
  # Workaround Mic92/sops-nix#910: stock Darwin activation races ahead of
  # setupLaunchAgents, so install secrets synchronously after linking the plist.
  # Secret-installation failures propagate; only launchctl reload is best-effort.
  config = lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isDarwin) {
    home.activation.sops-nix = lib.mkForce (
      lib.hm.dag.entryAfter [ "setupLaunchAgents" ] ''
        domain_target="gui/$(/usr/bin/id -u ${lib.escapeShellArg username})"
        plist=${lib.escapeShellArg "${homeDirectory}/Library/LaunchAgents/org.nix-community.home.sops-nix.plist"}
        /bin/launchctl bootout "$domain_target/org.nix-community.home.sops-nix" 2>/dev/null || true
        if [[ -f "$plist" ]]; then
          if ! program=$(/usr/bin/plutil -extract Program raw "$plist" 2>/dev/null); then
            printf '%s\n' "sops-nix: launch-agent plist has no Program entry: $plist" >&2
            exit 1
          fi
          if [[ ! -x "$program" ]]; then
            printf '%s\n' "sops-nix: secret installer is not executable: $program" >&2
            exit 1
          fi
          "$program"
          /bin/launchctl bootstrap "$domain_target" "$plist" 2>/dev/null || true
          /bin/launchctl kickstart -k "$domain_target/org.nix-community.home.sops-nix" 2>/dev/null || true
        fi
      ''
    );
  };
}
