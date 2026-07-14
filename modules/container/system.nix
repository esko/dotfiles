{ lib, pkgs, username, homeDirectory, ... }:

{
  # This target is only for a privileged Debian Trixie container that boots
  # systemd and intentionally behaves like a small machine. Normal OCI/dev
  # containers should continue using homeConfigurations.debianTrixie.
  nixpkgs.hostPlatform = "x86_64-linux";
  system-manager.allowAnyDistro = true;

  # Embedded Home Manager invokes Nix during its per-user activation service.
  nix.enable = true;

  # Trust only the System Manager cache and signing key; do not grant the
  # container user root-equivalent Nix trusted-user privileges.
  nix.settings = {
    substituters = lib.mkAfter [ "https://cache.numtide.com" ];
    trusted-substituters = [ "https://cache.numtide.com" ];
    trusted-public-keys = lib.mkAfter [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

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

  environment.systemPackages = with pkgs; [
    zsh
    tailscale
  ];

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
