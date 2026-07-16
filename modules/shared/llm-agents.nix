{ config, lib, pkgs, llmAgentPkgs ? null, ... }:

let
  agentAttrs = [
    "cursor-agent" # Cursor Agent CLI
    "antigravity-cli" # agy
    "claude-code" # claude
    "codex"
    "grok" # Grok Build
    "pi"
  ];

  cursorAgent = if llmAgentPkgs == null then null else llmAgentPkgs.cursor-agent or null;

  # Grok Build also ships bin/agent; keep that name for Cursor via the wrapper
  # below and expose only `grok` from the grok package.
  resolveAgentPackage = name:
    let package = llmAgentPkgs.${name} or null;
    in if package == null then
      null
    else if name == "grok" then
      package.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          rm -f "$out/bin/agent"
        '';
      })
    else
      package;

  agentPackages =
    if llmAgentPkgs == null then
      [ ]
    else
      lib.filter (pkg: pkg != null) (map resolveAgentPackage agentAttrs);

  agentCommand =
    if cursorAgent == null then
      null
    else
      pkgs.writeShellScriptBin "agent" ''
        exec ${lib.getExe cursorAgent} "$@"
      '';
in
{
  config = lib.mkIf (agentPackages != [ ]) {
    home.packages = agentPackages ++ lib.optional (agentCommand != null) agentCommand;
  };
}
