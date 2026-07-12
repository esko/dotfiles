{ pkgs, username, homeDirectory, ... }:

{
  # This target is only for a privileged Debian Trixie container that boots
  # systemd and intentionally behaves like a small machine. Normal OCI/dev
  # containers should continue using homeConfigurations.debianTrixie.
  nixpkgs.hostPlatform = "x86_64-linux";
  system-manager.allowAnyDistro = true;

  # Embedded Home Manager invokes Nix during its per-user activation service.
  nix.enable = true;

  services.userborn.enable = true;
  users.mutableUsers = true;
  users.users.root.enable = false;
  users.users.nobody.enable = false;

  users.groups.${username}.gid = 1000;
  users.users.${username} = {
    uid = 1000;
    isNormalUser = true;
    group = username;
    home = homeDirectory;
    createHome = true;
    shell = pkgs.zsh;

    # System Manager installs the shell into /run/system-manager/sw and Home
    # Manager provides the interactive startup files.
    ignoreShellProgramCheck = true;
  };

  environment.systemPackages = [ pkgs.zsh ];

  system-manager.preActivationAssertions.systemdContainer = {
    enable = true;
    script = ''
      init_comm=""
      IFS= read -r init_comm < /proc/1/comm || true
      if [ "$init_comm" != systemd ]; then
        echo "debianTrixieContainer requires systemd as PID 1."
        echo "Use homeConfigurations.debianTrixie for a normal OCI/dev container."
        exit 1
      fi
    '';
  };
}
