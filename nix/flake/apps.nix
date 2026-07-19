{
  pkgs,
  systemManagerPackage ? null,
}:

let
  # Thin store wrappers: secret scripts mutate the checkout, so the app must
  # locate and execute the working-tree script rather than inline its contents.
  mkDotfilesScriptApp =
    {
      name,
      scriptRelPath,
      prependArgs ? [ ],
    }:
    let
      prepend =
        if prependArgs == [ ] then
          ""
        else
          pkgs.lib.concatMapStringsSep " " pkgs.lib.escapeShellArg prependArgs;
      package = pkgs.writeShellApplication {
        inherit name;
        runtimeInputs = with pkgs; [
          age
          sops
          openssh
          git
          gh
          jq
          coreutils
          findutils
          gnugrep
          gnused
          gawk
          nix
        ];
        text = ''
          repo_root="''${SOPS_REPO_ROOT:-''${DOTFILES_FLAKE:-}}"
          if [[ -z "$repo_root" ]]; then
            repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
          fi
          script="$repo_root/${scriptRelPath}"
          if [[ -z "$repo_root" || ! -f "$script" ]]; then
            printf '%s\n' "${name}: run from the dotfiles checkout (or set SOPS_REPO_ROOT)" >&2
            exit 1
          fi
          export SOPS_REPO_ROOT="$repo_root"
          exec bash "$script" ${prepend} "$@"
        '';
      };
    in
    {
      type = "app";
      program = "${package}/bin/${name}";
    };
in
{
  bootstrap-secrets = mkDotfilesScriptApp {
    name = "bootstrap-secrets";
    scriptRelPath = "scripts/bootstrap-secrets.sh";
  };

  bootstrap-ssh = mkDotfilesScriptApp {
    name = "bootstrap-ssh";
    scriptRelPath = "scripts/bootstrap-secrets.sh";
    prependArgs = [ "ssh" ];
  };
}
// pkgs.lib.optionalAttrs (systemManagerPackage != null) {
  # Use the locked package so activation does not load the upstream flake's
  # nixConfig trust settings.
  system-manager = {
    type = "app";
    program = "${systemManagerPackage}/bin/system-manager";
  };
}
