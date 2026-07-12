{
  description = "Cross-platform dotfiles for Crostini, Baguette, Debian Trixie containers, and the Mac Mini";

  inputs = {
    # Linux is pinned to the nixpkgs revision used by the compatible System
    # Manager test matrix. Darwin remains on its dedicated 26.05 channel.
    nixpkgsLinux.url = "github:NixOS/nixpkgs/331800de5053fcebacf6813adb5db9c9dca22a0c";
    nixpkgsDarwin.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    homeManagerLinux = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgsLinux";
    };
    homeManagerDarwin = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgsDarwin";
    };

    system-manager = {
      # This post-1.1 revision contains the compatibility stubs required by
      # Home Manager 26.05, including system.userActivationScripts.
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
          builtins.elem (nixpkgsLinux.lib.getName pkg) [ "unrar" ];
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
      homeConfigurations.crostini = homeManagerLinux.lib.homeManagerConfiguration {
        pkgs = linuxPkgs;
        extraSpecialArgs = linuxArgs // { hostName = "crostini"; };
        modules = [
          sopsNixLinux.homeManagerModules.sops
          ./modules/shared/home.nix
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
          ./modules/shared/home.nix
          ./modules/container/home.nix
        ];
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
                ./modules/darwin/home.nix
              ];
            };
          }
        ];
      };
    };
}
