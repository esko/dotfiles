{
  nixDarwin,
  homeManager,
  sopsNix,
  darwinArgs,
  darwinSystem,
  username,
}:

nixDarwin.lib.darwinSystem {
  system = darwinSystem;
  specialArgs = darwinArgs;
  modules = [
    ../../../modules/darwin/system.nix
    {
      imports = [ sopsNix.darwinModules.sops ];
    }
    homeManager.darwinModules.home-manager
    {
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        backupFileExtension = "home-manager-backup";
        extraSpecialArgs = darwinArgs;
        users.${username} = {
          imports = [
            sopsNix.homeManagerModules.sops
            ../../../modules/shared/home.nix
            ../../../modules/shared/secrets.nix
            ../../../modules/darwin/home.nix
          ];

          # Mini's former Stow config directories are already real directories.
          # Restore Home Manager's normal collision checks for those paths.
          dotfiles.stowMigration.forceLegacyCollisions = false;
        };
      };
    }
  ];
}
