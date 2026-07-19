{
  homeManager,
  synologyPkgs,
  linuxPkgs,
  linuxLlmAgentPkgs,
  linuxArgs,
  linuxHome,
}:

let
  homeConfiguration = homeManager.lib.homeManagerConfiguration {
    pkgs = synologyPkgs;
    extraSpecialArgs = linuxArgs // {
      hostName = "synology-dev";
    };
    modules = [
      ../../../modules/shared/home.nix
      ../../../modules/container/home.nix
      {
        # The image has no legacy Stow files; collision replacement would hide
        # unexpected mutable-state conflicts rather than aid migration.
        dotfiles.stowMigration.forceLegacyCollisions = false;
        programs.zsh.history.path = "${linuxHome}/.local/state/zsh/history";
      }
    ];
  };

  bunBaseline = synologyPkgs.bun;
  opencodeBaseline = linuxLlmAgentPkgs.opencode.overrideAttrs (_oldAttrs: {
    version = "1.17.18";
    src = linuxPkgs.fetchurl {
      url = "https://github.com/anomalyco/opencode/releases/download/v1.17.18/opencode-linux-x64-baseline.tar.gz";
      hash = "sha256-yB1cRpIgYE9lBrCdxGVovN1V0tTmP2tKwj5izNjBlHk=";
    };
    # Colima's QEMU TCG cannot execute Bun-compiled payloads reliably. The
    # exact baseline payload is exercised directly on the target DS918+.
    doInstallCheck = false;
  });
  reasonixAgent = linuxLlmAgentPkgs.reasonix;
  hunkBaseline = synologyPkgs.callPackage ../../../packages/hunk-baseline.nix {
    inherit bunBaseline;
  };
  agentWorkspaceLinux =
    synologyPkgs.callPackage ../../../packages/agent-workspace-linux-baseline.nix
      { };
  synologyDevGui = synologyPkgs.callPackage ../../../packages/synology-dev-gui.nix { };
  synologyDevRoot = synologyPkgs.callPackage ../../../packages/synology-dev-root.nix {
    inherit
      homeConfiguration
      agentWorkspaceLinux
      reasonixAgent
      hunkBaseline
      opencodeBaseline
      synologyDevGui
      ;
  };
in
{
  inherit
    homeConfiguration
    agentWorkspaceLinux
    bunBaseline
    hunkBaseline
    opencodeBaseline
    synologyDevRoot
    ;
}
