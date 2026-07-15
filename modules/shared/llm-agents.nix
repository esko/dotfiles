{ config, lib, pkgs, llmAgentPkgs ? null, ... }:

let
  agentAttrs = [
    "cursor-agent" # Cursor Agent CLI
    "antigravity-cli" # agy
    "claude-code" # claude
    "codex"
    "pi"
  ];

  cursorAgent = if llmAgentPkgs == null then null else llmAgentPkgs.cursor-agent or null;

  agentPackages =
    if llmAgentPkgs == null then
      [ ]
    else
      lib.filter (pkg: pkg != null) (map (name: llmAgentPkgs.${name} or null) agentAttrs);

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
