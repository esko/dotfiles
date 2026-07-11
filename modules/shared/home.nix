{ config, lib, pkgs, username, homeDirectory, stateVersion, hostName, ... }:

let
  # A few fast-moving CLIs are not consistently packaged in every nixpkgs
  # revision. Keep them optional so the shared profile remains evaluable while
  # documenting the external install path in docs/shell-migration.md.
  optionalPackages = names:
    builtins.concatLists (map
      (name:
        if builtins.hasAttr name pkgs then
          let package = builtins.getAttr name pkgs;
          in lib.optional (lib.attrByPath [ "meta" "license" "free" ] true package) package
        else
          [ ])
      names);
in
{
  imports = [ ./llm-context.nix ];

  # Keep identity and state explicit so every host profile is reproducible.
  home.username = username;
  home.homeDirectory = homeDirectory;
  home.stateVersion = stateVersion;

  home.packages = with pkgs; [
    # Shell, navigation, search, and file tools.
    zsh starship zellij fzf zoxide git gh age bat eza fd ripgrep jq delta
    btop micro yazi rsync mosh shellcheck lefthook lazygit cmake

    # Language/toolchain foundations. fnm manages the active Node release;
    # Python is available for uv-managed virtual environments and pytest.
    rustup rustc cargo go zig fnm nodejs pnpm uv python3 pipx

    # Portable diagnostics and utilities audited from the existing hosts.
    curl wget openssh fastfetch p7zip unzip dos2unix dnsutils
    inetutils nmap bun cargo-binstall golangci-lint
    python3Packages.pytest croc
  ] ++ optionalPackages [
    # Optional package names vary by nixpkgs channel and should not block
    # profiles that use a leaner Trixie-compatible package set.
    "agent-browser" "agy" "antigravity" "athas" "claude-code" "codex"
    "command-code" "cursor-agent" "gemini-cli" "herdr" "hunkdiff" "jules"
    "pass-cli" "portless"
  ];

  # Keep existing utility configuration under declarative control. These are
  # repository files, so edits remain reviewable and are shared by all hosts.
  home.file.".config/bat/config".source = ../../utilities/.config/bat/config;
  home.file.".config/btop/btop.conf".source = ../../utilities/.config/btop/btop.conf;
  home.file.".config/micro/bindings.json".source = ../../utilities/.config/micro/bindings.json;
  home.file.".config/micro/settings.json".source = ../../utilities/.config/micro/settings.json;
  home.file.".config/zellij/config.kdl".source = ../../zellij/.config/zellij/config.kdl;

  programs.bat.enable = true;
  programs.fzf.enable = true;
  programs.zoxide = {
    enable = true;
    options = [ "--cmd=cd" ];
  };

  programs.starship = {
    enable = true;
    # Parse the existing Catppuccin Frappé Powerline configuration so the
    # migration preserves the prompt instead of silently replacing it.
    settings = builtins.fromTOML (builtins.readFile ../../starship/.config/starship.toml);
  };

  programs.zellij.enable = true;

  programs.git = {
    enable = true;
    ignores = [ ".DS_Store" ".direnv/" "result" "result-*" "*.swp" "*~" ];
    settings = {
      user.name = "Esko Pyyluoma";
      user.email = "esko.pyyluoma@gmail.com";
      core.pager = "hunk pager";
      merge.conflictStyle = "zdiff3";
      init.defaultBranch = "main";
      credential."https://github.com" = {
        helper = [ "" "!gh auth git-credential" ];
      };
      credential."https://gist.github.com" = {
        helper = [ "" "!gh auth git-credential" ];
      };
      url."git@github.com:".insteadOf = "https://github.com/";
    };
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    history = {
      size = 10000;
      save = 10000;
      extended = true;
      ignoreDups = true;
      share = true;
    };
    shellAliases = {
      # Safe file management and Fish-style command replacements.
      rm = "rm -iv";
      cp = "cp -riv";
      mv = "mv -iv";
      mkdir = "mkdir -p";
      cat = "bat";
      grep = "rg";
      find = "fd";
      lg = "lazygit";
      vim = "micro";
      ls = "eza --icons --group-directories-first";
      ll = "eza --long --all --header --icons";
      la = "eza --long --all --total-size --icons";
      lt = "eza --tree --icons";

      # Directory jumps and shell controls.
      desk = "cd ~/Desktop";
      docs = "cd ~/Documents";
      dl = "cd ~/Downloads";
      dev = "cd ~/dev";
      conf = "cd ~/dotfiles";
      reload = "exec zsh";
      q = "exit";
      c = "clear";

      # Git workflow and project tools.
      g = "git";
      gs = "git status -s";
      ga = "git add";
      gaa = "git add --all";
      gc = "git commit -m";
      gca = "git commit --amend -m";
      gco = "git checkout";
      gb = "git branch";
      gl = "git pull";
      gp = "git push";
      gd = "git diff";
      glg = "git log --stat";
      lh = "lefthook";

      # Zellij helpers retained from the Fish integration.
      zj = "zellij";
      za = "zellij action";
      ze = "zellij edit";
      zef = "zellij edit --floating";
      zr = "zellij run --";
      zrf = "zellij run --floating --";

    };
    initContent = builtins.readFile ./zsh/init.zsh;
  };

  # Shared environment paths mirror Fish's 01-env.fish and keep user-managed
  # language/package managers available without assuming a host OS.
  home.sessionVariables = {
    EDITOR = "micro";
    VISUAL = "micro";
    BUN_INSTALL = "$HOME/.bun";
    FNM_PATH = "$HOME/.local/share/fnm";
    NPM_CONFIG_PREFIX = "$HOME/.local";
  };
  home.sessionPath = [
    "$HOME/.bun/bin"
    "$HOME/.cargo/bin"
    "$HOME/.local/bin"
    "$HOME/bin"
    "$HOME/usr/local/bin"
  ];

  programs.home-manager.enable = true;

  dotfiles.llmContext.enable = true;
}
