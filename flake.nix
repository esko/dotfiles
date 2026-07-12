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
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nixpkgs, home-manager, nix-darwin, sops-nix, ... }:
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
      # Standalone Home Manager profile for the current Crostini host.
      homeConfigurations.crostini = home-manager.lib.homeManagerConfiguration {
        pkgs = linuxPkgs;
        extraSpecialArgs = linuxArgs // { hostName = "crostini"; };
        modules = [
          sops-nix.homeManagerModules.sops
          ./modules/shared/home.nix
          ./modules/linux/home.nix
        ];
      };

      # Baguette is the future native Debian/Trixie Linux host. Keep it on the
      # Linux host module rather than the headless container module: Docker,
      # GPU, keyring, device, and display integration remain host boundaries.
      homeConfigurations.baguette = home-manager.lib.homeManagerConfiguration {
        pkgs = linuxPkgs;
        extraSpecialArgs = linuxArgs // { hostName = "baguette"; };
        modules = [
          sops-nix.homeManagerModules.sops
          ./modules/shared/home.nix
          ./modules/linux/home.nix
        ];
      };

      # Deliberately minimal profile for Debian Trixie containers. Host GUI,
      # Docker, keyring, and device integration stay outside this output.
      homeConfigurations.debianTrixie = home-manager.lib.homeManagerConfiguration {
        pkgs = linuxPkgs;
        extraSpecialArgs = linuxArgs // { hostName = "debian-trixie"; };
        modules = [
          ./modules/shared/home.nix
          ./modules/container/home.nix
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
