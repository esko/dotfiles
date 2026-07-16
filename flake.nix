{
  description = "Cross-platform dotfiles for Baguette, the Synology dev container, and the Mac Mini";

  # llm-agents.nix publishes daily builds to Numtide's cache. Without this,
  # following the flake as an input falls back to cache.nixos.org only and can
  # rebuild large agent closures from source on Baguette.
  nixConfig = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  inputs = {
    # Linux follows the current unstable package set while flake.lock keeps each
    # reviewed deployment reproducible. Darwin remains on its dedicated 26.05
    # release channel.
    nixpkgsLinux.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgsDarwin.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    homeManagerLinux = {
      # This revision declares Home Manager 26.11, matching the Linux nixpkgs
      # release. The earlier c909892 revision still declared 26.05 and
      # therefore correctly triggered Home Manager's release mismatch warning.
      url = "github:nix-community/home-manager/7566825d4652a1b885bd4ce65bd9e8def432fec9";
      inputs.nixpkgs.follows = "nixpkgsLinux";
    };
    homeManagerDarwin = {
      # Pin includes docs/default.nix fix for Determinate Nix options.json
      # warnings (nix-community/home-manager@4c11a945) until release-26.05
      # absorbs it.
      url = "github:nix-community/home-manager/4c11a945f40cdd2c74307048204b71305dffd562";
      inputs.nixpkgs.follows = "nixpkgsDarwin";
    };

    system-manager = {
      # This post-1.1 revision contains the compatibility stubs required by
      # current Home Manager, including system.userActivationScripts.
      url = "github:numtide/system-manager/96f724be6f1411286e8ad0202e3e624c10116a6d";
      inputs.nixpkgs.follows = "nixpkgsLinux";
    };

    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgsDarwin";

    sopsNixLinux = {
      url = "github:Mic92/sops-nix/8eaee5c45428b28b8c47a83e4c09dccec5f279b5";
      inputs.nixpkgs.follows = "nixpkgsLinux";
    };
    sopsNixDarwin = {
      # Keep the same reviewed revision as Linux so secret decryption behavior
      # does not diverge across hosts on the next flake update.
      url = "github:Mic92/sops-nix/8eaee5c45428b28b8c47a83e4c09dccec5f279b5";
      inputs.nixpkgs.follows = "nixpkgsDarwin";
    };

    # Fast-moving agent CLIs with daily package updates and a dedicated cache.
    llmAgents.url = "github:numtide/llm-agents.nix";

  };

  outputs = inputs@{
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

      llmAgentPkgsFor = system: llmAgents.packages.${system};
      linuxLlmAgentPkgs = llmAgentPkgsFor linuxSystem;
      darwinLlmAgentPkgs = llmAgentPkgsFor darwinSystem;

      linuxPkgs = import nixpkgsLinux {
        system = linuxSystem;
        config.allowUnfreePredicate = pkg:
          builtins.elem (nixpkgsLinux.lib.getName pkg) [
            "antigravity-cli"
            "antigravity"
            # pkgs.code-cursor reports lib.getName "cursor"
            "cursor"
            "unrar"
          ];
      };
      synologyPkgs = linuxPkgs.extend (final: _previous: {
        # The DS918+'s J3455 has no AVX/AVX2. Keep the `bun` selected by the
        # shared Home Manager module on Bun's published baseline build.
        bun = final.callPackage ./packages/bun-baseline.nix { };
        # Keep the shared profile's optional Herdr entry identical to the
        # llm-agents package explicitly added to the runtime closure.
        herdr = linuxLlmAgentPkgs.herdr;
      });
      darwinPkgs = import nixpkgsDarwin {
        system = darwinSystem;
      };

      inkscapeBeta = linuxPkgs.callPackage ./packages/inkscape-beta.nix { };

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

      mkBootstrapSecretsApp = pkgs:
        let
          package = pkgs.writeShellApplication {
            name = "bootstrap-secrets";
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
            text = builtins.readFile ./scripts/bootstrap-secrets.sh;
          };
        in {
          type = "app";
          program = "${package}/bin/bootstrap-secrets";
        };

      mkBootstrapSshApp = pkgs:
        let
          package = pkgs.writeShellApplication {
            name = "bootstrap-ssh";
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
            text = builtins.readFile ./scripts/bootstrap-ssh.sh;
          };
        in {
          type = "app";
          program = "${package}/bin/bootstrap-ssh";
        };

      secretsManifest = import ./secrets/manifest.nix;

      synologyDevHome = homeManagerLinux.lib.homeManagerConfiguration {
        pkgs = synologyPkgs;
        extraSpecialArgs = linuxArgs // { hostName = "synology-dev"; };
        modules = [
          ./modules/shared/home.nix
          ./modules/container/home.nix
          {
            # Persist history beneath the mutable state mount rather than next
            # to image-owned Home Manager symlinks.
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
      # Agents already in the Synology Home Manager profile come from
      # home.path. Only packages outside that profile are passed explicitly.
      reasonixAgent = linuxLlmAgentPkgs.reasonix;
      hunkBaseline = synologyPkgs.callPackage ./packages/hunk-baseline.nix {
        inherit bunBaseline;
      };
      agentWorkspaceLinux = synologyPkgs.callPackage ./packages/agent-workspace-linux-baseline.nix { };
      synologyDevGui = synologyPkgs.callPackage ./packages/synology-dev-gui.nix { };
      synologyDevRoot = synologyPkgs.callPackage ./packages/synology-dev-root.nix {
        homeConfiguration = synologyDevHome;
        inherit
          agentWorkspaceLinux
          reasonixAgent
          hunkBaseline
          opencodeBaseline
          synologyDevGui
          ;
      };
    in {
      apps.${linuxSystem}.bootstrap-secrets = mkBootstrapSecretsApp linuxPkgs;
      apps.${linuxSystem}.bootstrap-ssh = mkBootstrapSshApp linuxPkgs;
      apps.${darwinSystem}.bootstrap-secrets = mkBootstrapSecretsApp darwinPkgs;
      apps.${darwinSystem}.bootstrap-ssh = mkBootstrapSshApp darwinPkgs;

      inherit secretsManifest;

      # Native Debian/Trixie host. System Manager owns the reviewed root-level
      # boundary and activates Home Manager for the existing esko account.
      systemConfigs.baguette = system-manager.lib.makeSystemConfig {
        specialArgs = linuxArgs // { hostName = "baguette"; };
        modules = [
          homeManagerLinux.nixosModules.home-manager
          ./modules/linux/system.nix
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "home-manager-backup";
              extraSpecialArgs = linuxArgs // {
                hostName = "baguette";
                # Baguette uses the pinned 1.5-dev AppImage instead of nixpkgs 1.4.x.
                inherit inkscapeBeta;
              };
              users.${username} = {
                imports = [
                  sopsNixLinux.homeManagerModules.sops
                  ./modules/shared/home.nix
                  ./modules/shared/secrets.nix
                  ./modules/linux/home.nix
                ];
              };
            };
          }
        ];
      };

      # Home Manager evaluation embedded into the unprivileged Synology image.
      # It deliberately omits the SOPS/SSH module so no host identity can enter
      # an image layer.
      homeConfigurations.synologyDev = synologyDevHome;

      packages.${linuxSystem} = {
        inherit bunBaseline hunkBaseline opencodeBaseline synologyDevRoot inkscapeBeta;
      };

      # Expose the System Manager derivations through the standard flake check
      # interface so `nix flake check` evaluates the Linux configurations
      # instead of silently skipping the custom output.
      checks.${linuxSystem} = {
        baguette = self.systemConfigs.baguette;
        synologyDevRoot = synologyDevRoot;
      };

      # nix-darwin owns the Mac host and embeds Home Manager for the user.
      darwinConfigurations.mini = nix-darwin.lib.darwinSystem {
        system = darwinSystem;
        specialArgs = darwinArgs;
        modules = [
          ./modules/darwin/system.nix
          {
            imports = [ sopsNixDarwin.darwinModules.sops ];
          }
          homeManagerDarwin.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "home-manager-backup";
            home-manager.extraSpecialArgs = darwinArgs;
            home-manager.users.${username} = {
              imports = [
                sopsNixDarwin.homeManagerModules.sops
                ./modules/shared/home.nix
                ./modules/shared/secrets.nix
                ./modules/darwin/home.nix
              ];
            };
          }
        ];
      };
    };
}
