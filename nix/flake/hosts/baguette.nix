{
  systemManager,
  homeManager,
  sopsNix,
  linuxArgs,
  username,
  inkscapeBeta,
}:

systemManager.lib.makeSystemConfig {
  specialArgs = linuxArgs // {
    hostName = "baguette";
    inherit inkscapeBeta;
  };
  modules = [
    homeManager.nixosModules.home-manager
    ../../../modules/linux/system.nix
    ../../../modules/linux/crostini-launchers.nix
    {
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        backupFileExtension = "home-manager-backup";
        extraSpecialArgs = linuxArgs // {
          hostName = "baguette";
          inherit inkscapeBeta;
        };
        users.${username}.imports = [
          sopsNix.homeManagerModules.sops
          ../../../modules/shared/home.nix
          ../../../modules/shared/secrets.nix
          ../../../modules/linux/home.nix
        ];
      };
    }
  ];
}
