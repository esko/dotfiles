{
  config,
  lib,
  pkgs,
  llmAgentPkgs ? null,
  ...
}:

let
  requiredAgentAttrs = [
    "cursor-agent" # Cursor Agent CLI
    "antigravity-cli" # agy
    "claude-code" # claude
    "codex"
    "grok" # Grok Build
    "pi"
  ];

  hasAgentPackage =
    name:
    llmAgentPkgs != null
    && builtins.hasAttr name llmAgentPkgs
    && builtins.getAttr name llmAgentPkgs != null;

  missingAgentAttrs =
    if llmAgentPkgs == null then
      [ ]
    else
      lib.filter (name: !hasAgentPackage name) requiredAgentAttrs;

  cursorAgent = if hasAgentPackage "cursor-agent" then llmAgentPkgs.cursor-agent else null;

  # Grok Build also ships bin/agent; keep that name for Cursor via the wrapper
  # below and expose only `grok` from the grok package.
  resolveAgentPackage =
    name:
    let
      package = builtins.getAttr name llmAgentPkgs;
    in
    if name == "grok" then
      package.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          rm -f "$out/bin/agent"
        '';
      })
    else
      package;

  agentPackages =
    if llmAgentPkgs == null || missingAgentAttrs != [ ] then
      [ ]
    else
      map resolveAgentPackage requiredAgentAttrs;

  agentCommand =
    if cursorAgent == null then
      null
    else
      pkgs.writeShellScriptBin "agent" ''
        exec ${lib.getExe cursorAgent} "$@"
      '';
in
{
  assertions = [
    {
      assertion = llmAgentPkgs == null || missingAgentAttrs == [ ];
      message = "llm-agents package set is missing required attributes: ${
        lib.concatStringsSep ", " missingAgentAttrs
      }";
    }
  ];

  config = lib.mkIf (agentPackages != [ ]) {
    home.packages = agentPackages ++ lib.optional (agentCommand != null) agentCommand;
  };
}
