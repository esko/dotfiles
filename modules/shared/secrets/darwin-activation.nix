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
          if program=$(/usr/bin/plutil -extract Program raw "$plist" 2>/dev/null); then
            if [[ ! -x "$program" ]]; then
              printf '%s\n' "sops-nix: secret installer is not executable: $program" >&2
              exit 1
            fi
            "$program"
          elif arguments_json=$(/usr/bin/plutil -extract ProgramArguments json -o - "$plist" 2>/dev/null); then
            # Home Manager rewrites launch agents through /bin/wait4path and
            # therefore emits ProgramArguments even when sops-nix set Program.
            program_args=()
            while IFS= read -r -d "" argument; do
              program_args+=("$argument")
            done < <(printf '%s' "$arguments_json" | ${pkgs.jq}/bin/jq -j '.[] | ., "\u0000"')

            if (( ''${#program_args[@]} == 0 )); then
              printf '%s\n' "sops-nix: launch-agent plist has empty ProgramArguments: $plist" >&2
              exit 1
            fi
            if [[ ! -x "''${program_args[0]}" ]]; then
              printf '%s\n' "sops-nix: launch-agent executable is not executable: ''${program_args[0]}" >&2
              exit 1
            fi
            "''${program_args[@]}"
          else
            printf '%s\n' "sops-nix: launch-agent plist has neither Program nor ProgramArguments: $plist" >&2
            exit 1
          fi
          /bin/launchctl bootstrap "$domain_target" "$plist" 2>/dev/null || true
          /bin/launchctl kickstart -k "$domain_target/org.nix-community.home.sops-nix" 2>/dev/null || true
        fi
      ''
    );
  };
}
