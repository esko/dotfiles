{ config, lib, pkgs, username, homeDirectory, stateVersion, hostName, ... }:

{
  # Keep the Debian Trixie container profile smaller than the Linux workstation.
  # Host services, Docker, GUI applications, and device integration do not
  # belong in this Home Manager output.
}
