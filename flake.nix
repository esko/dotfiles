{
  description = "Cross-platform dotfiles for Crostini, Baguette, Debian Trixie containers, and the Mac Mini";

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
      url = "github:nix-community/home-manager/release-26.05";
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
      url = "github:Mic92/sops-nix";
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

      linuxPkgs = import nixpkgsLinux {
        system = linuxSystem;
        config.allowUnfreePredicate = pkg:
          builtins.elem (nixpkgsLinux.lib.getName pkg) [
            "antigravity-cli"
            "unrar"
          ];
      };
      synologyPkgs = linuxPkgs.extend (final: _previous: {
        # The DS918+'s J3455 has no AVX/AVX2. Keep the `bun` selected by the
        # shared Home Manager module on Bun's published baseline build.
        bun = final.callPackage ./packages/bun-baseline.nix { };
        # Keep the shared profile's optional Herdr entry identical to the
        # llm-agents package explicitly added to the runtime closure.
        herdr = llmAgentPkgs.herdr;
      });
      darwinPkgs = import nixpkgsDarwin {
        system = darwinSystem;
      };

      linuxArgs = {
        inherit username stateVersion;
        homeDirectory = linuxHome;
      };
      darwinArgs = {
        inherit username stateVersion;
        homeDirectory = darwinHome;
        hostName = "mini";
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
              coreutils
              findutils
              gnugrep
              gnused
              gawk
            ];
            text = builtins.readFile ./scripts/bootstrap-ssh.sh;
          };
        in {
          type = "app";
          program = "${package}/bin/bootstrap-ssh";
        };

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
      llmAgentPkgs = llmAgents.packages.${linuxSystem};
      opencodeBaseline = llmAgentPkgs.opencode.overrideAttrs (_oldAttrs: {
        version = "1.17.18";
        src = linuxPkgs.fetchurl {
          url = "https://github.com/anomalyco/opencode/releases/download/v1.17.18/opencode-linux-x64-baseline.tar.gz";
          hash = "sha256-yB1cRpIgYE9lBrCdxGVovN1V0tTmP2tKwj5izNjBlHk=";
        };
        # Colima's QEMU TCG cannot execute Bun-compiled payloads reliably. The
        # exact baseline payload is exercised directly on the target DS918+.
        doInstallCheck = false;
      });
      codexAgent = llmAgentPkgs.codex;
      antigravityCli = llmAgentPkgs.antigravity-cli;
      herdrAgent = llmAgentPkgs.herdr;
      hunkBaseline = synologyPkgs.callPackage ./packages/hunk-baseline.nix {
        inherit bunBaseline;
      };
      synologyDevRoot = synologyPkgs.callPackage ./packages/synology-dev-root.nix {
        homeConfiguration = synologyDevHome;
        inherit antigravityCli codexAgent herdrAgent hunkBaseline opencodeBaseline;
      };
    in {
      apps.${linuxSystem}.bootstrap-ssh = mkBootstrapSshApp linuxPkgs;
      apps.${darwinSystem}.bootstrap-ssh = mkBootstrapSshApp darwinPkgs;

      # Standalone Home Manager profile for the current Crostini host. ChromeOS
      # and the Crostini VM remain responsible for system-level configuration.
      homeConfigurations.crostini = homeManagerLinux.lib.homeManagerConfiguration {
        pkgs = linuxPkgs;
        extraSpecialArgs = linuxArgs // { hostName = "crostini"; };
        modules = [
          sopsNixLinux.homeManagerModules.sops
          ./modules/shared/home.nix
          ./modules/shared/ssh.nix
          ./modules/linux/home.nix
        ];
      };

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
              extraSpecialArgs = linuxArgs // { hostName = "baguette"; };
              users.${username} = {
                imports = [
                  sopsNixLinux.homeManagerModules.sops
                  ./modules/shared/home.nix
                  ./modules/shared/ssh.nix
                  ./modules/linux/home.nix
                ];
              };
            };
          }
        ];
      };

      # Lightweight OCI/dev-container profile. It intentionally does not mutate
      # /etc, create users, or require systemd/privileged activation.
      homeConfigurations.debianTrixie = homeManagerLinux.lib.homeManagerConfiguration {
        pkgs = linuxPkgs;
        extraSpecialArgs = linuxArgs // { hostName = "debian-trixie"; };
        modules = [
          sopsNixLinux.homeManagerModules.sops
          ./modules/shared/home.nix
          ./modules/shared/ssh.nix
          ./modules/container/home.nix
        ];
      };

      # Home Manager evaluation embedded into the unprivileged Synology image.
      # It deliberately omits the SOPS/SSH module so no host identity can enter
      # an image layer.
      homeConfigurations.synologyDev = synologyDevHome;

      packages.${linuxSystem} = {
        inherit bunBaseline hunkBaseline opencodeBaseline synologyDevRoot;
      };

      # Optional machine-like container profile for a privileged Debian Trixie
      # container that boots systemd. Normal containers must use the standalone
      # Home Manager output above.
      systemConfigs.debianTrixieContainer = system-manager.lib.makeSystemConfig {
        specialArgs = linuxArgs // { hostName = "debian-trixie-container"; };
        modules = [
          homeManagerLinux.nixosModules.home-manager
          ./modules/container/system.nix
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "home-manager-backup";
              extraSpecialArgs = linuxArgs // { hostName = "debian-trixie-container"; };
              users.${username} = {
                imports = [
                  sopsNixLinux.homeManagerModules.sops
                  ./modules/shared/home.nix
                  ./modules/shared/ssh.nix
                  ./modules/container/home.nix
                ];
              };
            };
          }
        ];
      };

      # Expose the System Manager derivations through the standard flake check
      # interface so `nix flake check` evaluates both machine-like Linux
      # configurations instead of silently skipping the custom output.
      checks.${linuxSystem} = {
        baguette = self.systemConfigs.baguette;
        debianTrixieContainer = self.systemConfigs.debianTrixieContainer;
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
            home-manager.extraSpecialArgs = darwinArgs;
            home-manager.users.${username} = {
              imports = [
                sopsNixDarwin.homeManagerModules.sops
                ./modules/shared/home.nix
                ./modules/shared/ssh.nix
                ./modules/darwin/home.nix
              ];
            };
          }
        ];
      };
    };
}
