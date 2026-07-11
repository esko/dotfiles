{ config, lib, ... }:

let
  cfg = config.dotfiles.llmContext;
in
{
  options.dotfiles.llmContext = {
    enable = lib.mkEnableOption "private LLM context integration";

    contextDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.local/share/llm-context";
      description = "Path to the optional private LLM context checkout.";
    };

    seedDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.codex/memories";
      description = "Path to the local Codex memory seed directory.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.sessionVariables = {
      LLM_CONTEXT_DIR = cfg.contextDir;
      LLM_CONTEXT_SEED = cfg.seedDir;
    };

    # The source tree is public and sanitized. It is useful even before the
    # optional private checkout has been cloned.
    xdg.configFile."llm-context/templates".source = ../../templates/llm-context;
    home.file.".local/bin/llm-context-sync".source = ../../scripts/llm-context-sync;
  };
}
