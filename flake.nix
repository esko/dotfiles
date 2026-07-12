{
  description = "Cross-platform dotfiles for Crostini, Baguette, Debian Trixie containers, and the Mac Mini";

  inputs = {
    # These release branches are intentionally conservative. `nix flake lock`
    # records the immutable revisions used by each checkout.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    system-manager = {
      url = "github:numtide/system-manager/v1.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{
    self,
    nixpkgs,
    home-manager,
    system-manager,
    nix-darwin,
    sops-nix,
    ...
  }:
    let
      username = "esko";
      linuxHome = "/home/esko";
      darwinHome = "/Users/esko";
      stateVersion = "26.05";

      linuxSystem = "x86_64-linux";
      darwinSystem = "aarch64-darwin";

      linuxPkgs = import nixpkgs {
        system = linuxSystem;
        config.allowUnfreePredicate = pkg:
          builtins.elem (nixpkgs.lib.getName pkg) [ "unrar" ];
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
    in {
      # Standalone Home Manager profile for the current Crostini host. ChromeOS
      # and the Crostini VM remain responsible for system-level configuration.
      homeConfigurations.crostini = home-manager.lib.homeManagerConfiguration {
        pkgs = linuxPkgs;
        extraSpecialArgs = linuxArgs // { hostName = "crostini"; };
        modules = [
          sops-nix.homeManagerModules.sops
          ./modules/shared/home.nix
          ./modules/linux/home.nix
        ];
      };

      # Native Debian/Trixie host. System Manager owns the reviewed root-level
      # boundary and activates Home Manager for the existing esko account.
      systemConfigs.baguette = system-manager.lib.makeSystemConfig {
        # System Manager v1.1.0 calls this extraSpecialArgs. The newer
        # specialArgs spelling is not accepted by the pinned release.
        extraSpecialArgs = linuxArgs // { hostName = "baguette"; };
        modules = [
          home-manager.nixosModules.home-manager
          ./modules/linux/system.nix
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "home-manager-backup";
              extraSpecialArgs = linuxArgs // { hostName = "baguette"; };
              users.${username} = {
                imports = [
                  sops-nix.homeManagerModules.sops
                  ./modules/shared/home.nix
                  ./modules/linux/home.nix
                ];
              };
            };
          }
        ];
      };

      # Lightweight OCI/dev-container profile. It intentionally does not mutate
      # /etc, create users, or require systemd/privileged activation.
      homeConfigurations.debianTrixie = home-manager.lib.homeManagerConfiguration {
        pkgs = linuxPkgs;
        extraSpecialArgs = linuxArgs // { hostName = "debian-trixie"; };
        modules = [
          ./modules/shared/home.nix
          ./modules/container/home.nix
        ];
      };

      # Optional machine-like container profile for a privileged Debian Trixie
      # container that boots systemd. Normal containers must use the standalone
      # Home Manager output above.
      systemConfigs.debianTrixieContainer = system-manager.lib.makeSystemConfig {
        extraSpecialArgs = linuxArgs // { hostName = "debian-trixie-container"; };
        modules = [
          home-manager.nixosModules.home-manager
          ./modules/container/system.nix
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "home-manager-backup";
              extraSpecialArgs = linuxArgs // { hostName = "debian-trixie-container"; };
              users.${username} = {
                imports = [
                  ./modules/shared/home.nix
                  ./modules/container/home.nix
                ];
              };
            };
          }
        ];
      };

      # nix-darwin owns the Mac host and embeds Home Manager for the user.
      darwinConfigurations.mini = nix-darwin.lib.darwinSystem {
        system = darwinSystem;
        specialArgs = darwinArgs;
        modules = [
          ./modules/darwin/system.nix
          {
            imports = [ sops-nix.darwinModules.sops ];
          }
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = darwinArgs;
            home-manager.users.${username} = {
              imports = [
                sops-nix.homeManagerModules.sops
                ./modules/shared/home.nix
                ./modules/darwin/home.nix
              ];
            };
          }
        ];
      };
    };
}
