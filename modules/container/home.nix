{
  config,
  lib,
  pkgs,
  username,
  homeDirectory,
  stateVersion,
  hostName,
  ...
}:

let
  inherit (lib) mkIf mkOption types;
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
    # These four are container foundations: reference them directly so a
    # missing attr fails evaluation loudly instead of being silently skipped.
    # (nixpkgs exposes CA certs as `cacert`, not `ca-certificates`.)
    home.packages =
      lib.optionals config.dotfiles.container.enableSharedTools [
        pkgs.cacert
        pkgs.openssh
        pkgs.procps
        pkgs.which
      ]
      ++ lib.optionals config.dotfiles.container.allowGuiPackages config.dotfiles.container.guiPackages;

    # LiteLLM on the Synology host is published on :4000. From this macvlan
    # container the host is reachable via the macvlan_bridge gateway 10.10.0.1.
    home.file.".grok/config.toml" = {
      source = ../../config/synology-dev/grok/config.toml;
      force = config.dotfiles.stowMigration.forceLegacyCollisions;
    };

    # Load virtual keys when present (not in git). Prefer the state mount so
    # keys survive image recreates on the current Compose volume layout.
    programs.zsh.initContent = lib.mkAfter ''
      for _grok_keys in \
        "$HOME/.local/state/grok-litellm-harness/virtual-keys.env" \
        "$HOME/.config/grok-litellm-harness/virtual-keys.env"
      do
        if [[ -f "$_grok_keys" ]]; then
          set -a
          # shellcheck disable=SC1090
          . "$_grok_keys"
          set +a
          break
        fi
      done
      unset _grok_keys
    '';
  };
}
