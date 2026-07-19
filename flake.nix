{
  description = "Cross-platform dotfiles for Baguette, the Synology dev container, and the Mac Mini";

  # Do not set nixConfig.extra-trusted-public-keys here. Determinate Nix leaves
  # unprivileged users untrusted, so flake-supplied trust settings only warn.
  # scripts/enable-numtide-cache.sh manages /etc/nix/nix.custom.conf instead.

  inputs = {
    # Linux follows unstable while flake.lock preserves reviewed deployments.
    # Darwin remains on its dedicated 26.05 release channel.
    nixpkgsLinux.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgsDarwin.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    homeManagerLinux = {
      # Declares Home Manager 26.11, matching the Linux nixpkgs release.
      url = "github:nix-community/home-manager/7566825d4652a1b885bd4ce65bd9e8def432fec9";
      inputs.nixpkgs.follows = "nixpkgsLinux";
    };
    homeManagerDarwin = {
      # Includes the Determinate Nix options.json warning fix.
      url = "github:nix-community/home-manager/4c11a945f40cdd2c74307048204b71305dffd562";
      inputs.nixpkgs.follows = "nixpkgsDarwin";
    };

    system-manager = {
      # flake.lock pins the reviewed revision. Current upstream recognizes
      # Debian and includes the Home Manager compatibility stubs we require.
      url = "github:numtide/system-manager";
      inputs.nixpkgs.follows = "nixpkgsLinux";
    };

    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgsDarwin";

    sopsNixLinux = {
      url = "github:Mic92/sops-nix/8eaee5c45428b28b8c47a83e4c09dccec5f279b5";
      inputs.nixpkgs.follows = "nixpkgsLinux";
    };
    sopsNixDarwin = {
      url = "github:Mic92/sops-nix/8eaee5c45428b28b8c47a83e4c09dccec5f279b5";
      inputs.nixpkgs.follows = "nixpkgsDarwin";
    };

    # Fast-moving agent CLIs with daily package updates and a dedicated cache.
    llmAgents.url = "github:numtide/llm-agents.nix";
  };

  outputs =
    inputs@{
      self,
      nixpkgsLinux,
      nixpkgsDarwin,
      homeManagerLinux,
      homeManagerDarwin,
      system-manager,
      nix-darwin,
      sopsNixLinux,
      sopsNixDarwin,
      llmAgents,
      ...
    }:
    let
      username = "esko";
      linuxHome = "/home/esko";
      darwinHome = "/Users/esko";
      stateVersion = "26.05";
      linuxSystem = "x86_64-linux";
      darwinSystem = "aarch64-darwin";

      linuxLlmAgentPkgs = llmAgents.packages.${linuxSystem};
      darwinLlmAgentPkgs = llmAgents.packages.${darwinSystem};

      linuxPkgs = import nixpkgsLinux {
        system = linuxSystem;
        config.allowUnfreePredicate =
          pkg:
          builtins.elem (nixpkgsLinux.lib.getName pkg) [
            "antigravity-cli"
            "antigravity"
            # pkgs.code-cursor reports lib.getName "cursor".
            "cursor"
            "unrar"
          ];
      };
      synologyPkgs = linuxPkgs.extend (
        final: _previous: {
          # The DS918+'s J3455 has no AVX/AVX2.
          bun = final.callPackage ./packages/bun-baseline.nix { };
          herdr = linuxLlmAgentPkgs.herdr;
        }
      );
      darwinPkgs = import nixpkgsDarwin { system = darwinSystem; };

      linuxArgs = {
        inherit username stateVersion;
        homeDirectory = linuxHome;
        llmAgentPkgs = linuxLlmAgentPkgs;
      };
      darwinArgs = {
        inherit username stateVersion;
        homeDirectory = darwinHome;
        hostName = "mini";
        llmAgentPkgs = darwinLlmAgentPkgs;
      };

      inkscapeBeta = linuxPkgs.callPackage ./packages/inkscape-beta.nix { };
      synologyDevbox = import ./nix/flake/hosts/synology-devbox.nix {
        inherit
          synologyPkgs
          linuxPkgs
          linuxLlmAgentPkgs
          linuxArgs
          linuxHome
          ;
        homeManager = homeManagerLinux;
      };
      baguette = import ./nix/flake/hosts/baguette.nix {
        inherit
          linuxArgs
          username
          inkscapeBeta
          ;
        systemManager = system-manager;
        homeManager = homeManagerLinux;
        sopsNix = sopsNixLinux;
      };
      mini = import ./nix/flake/hosts/mini.nix {
        inherit
          darwinArgs
          darwinSystem
          username
          ;
        nixDarwin = nix-darwin;
        homeManager = homeManagerDarwin;
        sopsNix = sopsNixDarwin;
      };

      staticChecksFor = pkgs: system: (import ./nix/checks/static.nix) { inherit pkgs self system; };
      staticChecksLinux = staticChecksFor linuxPkgs linuxSystem;
      staticChecksDarwin = staticChecksFor darwinPkgs darwinSystem;
      systemManagerPackage = system-manager.packages.${linuxSystem}.default;
    in
    {
      # Each supported system owns one apps attrset; split dynamic assignments
      # collide under newer Nix.
      apps = {
        ${linuxSystem} = import ./nix/flake/apps.nix {
          pkgs = linuxPkgs;
          inherit systemManagerPackage;
        };
        ${darwinSystem} = import ./nix/flake/apps.nix { pkgs = darwinPkgs; };
      };

      secretsManifest = import ./secrets/manifest.nix;

      # Native Debian/Trixie host. System Manager owns only the reviewed
      # root-level boundary and activates HM for the existing account.
      systemConfigs.baguette = baguette;

      # The unprivileged image deliberately omits SOPS/SSH so no host identity
      # can enter an image layer.
      homeConfigurations.synologyDevbox = synologyDevbox.homeConfiguration;

      packages.${linuxSystem} = {
        inherit inkscapeBeta;
        inherit (synologyDevbox)
          agentWorkspaceLinux
          bunBaseline
          hunkBaseline
          opencodeBaseline
          synologyDevRoot
          ;
        system-manager = systemManagerPackage;
      };

      checks.${linuxSystem} = staticChecksLinux // {
        agentWorkspaceSmoke = synologyDevbox.agentWorkspaceLinux.tests.smoke;
        baguette = self.systemConfigs.baguette;
        hunkSmoke = synologyDevbox.hunkBaseline.tests.smoke;
        inkscapeSmoke = inkscapeBeta.tests.smoke;
        synologyDevRoot = synologyDevbox.synologyDevRoot;
      };
      checks.${darwinSystem} = staticChecksDarwin // {
        mini = self.darwinConfigurations.mini.system;
      };

      formatter.${linuxSystem} = linuxPkgs.nixfmt;
      formatter.${darwinSystem} = darwinPkgs.nixfmt;

      darwinConfigurations.mini = mini;
    };
}
