{ config, lib, pkgs, username, homeDirectory, stateVersion, hostName, ... }:

{
  system.primaryUser = username;
  users.users.${username}.home = homeDirectory;

  # Homebrew is an integration point for host applications. Never remove or
  # zap unmanaged software during activation; package selections come later.
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      upgrade = false;
      cleanup = "none";
    };
  };
}
