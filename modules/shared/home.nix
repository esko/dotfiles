{ config, lib, pkgs, username, homeDirectory, stateVersion, hostName, ... }:

{
  # Keep identity and state explicit so every host profile is reproducible.
  home.username = username;
  home.homeDirectory = homeDirectory;
  home.stateVersion = stateVersion;

  # Shared programs and packages are intentionally added in a later slice.
  programs.home-manager.enable = true;
}
