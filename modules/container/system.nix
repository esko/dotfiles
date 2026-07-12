{ pkgs, username, homeDirectory, ... }:

{
  # This target is only for a privileged Debian Trixie container that boots
  # systemd and intentionally behaves like a small machine. Normal OCI/dev
  # containers should continue using homeConfigurations.debianTrixie.
  nixpkgs.hostPlatform = "x86_64-linux";
  system-manager.allowAnyDistro = true;

  services.userborn.enable = true;
  users.mutableUsers = true;

  users.groups.${username}.gid = 1000;
  users.users.${username} = {
    uid = 1000;
    isNormalUser = true;
    group = username;
    home = homeDirectory;
    createHome = true;
    shell = pkgs.zsh;

    # System Manager v1.1.0 does not import the full NixOS zsh module. The shell
    # is installed into /run/system-manager/sw and Home Manager provides the
    # interactive startup files.
    ignoreShellProgramCheck = true;
  };

  environment.systemPackages = [ pkgs.zsh ];

  system-manager.preActivationAssertions.systemdContainer = {
    enable = true;
    script = ''
      if [ "$(/usr/bin/ps -p 1 -o comm= | /usr/bin/tr -d ' ')" != systemd ]; then
        echo "debianTrixieContainer requires systemd as PID 1."
        echo "Use homeConfigurations.debianTrixie for a normal OCI/dev container."
        exit 1
      fi
    '';
  };
}
