{ lib, username, homeDirectory, ... }:

{
  # Baguette is Debian Trixie running on x86_64 hardware. System Manager owns
  # only the reviewed system-level boundary; Debian still owns the kernel,
  # bootloader, hardware drivers, display manager, apt repositories, and the
  # existing Determinate Nix installation and configuration.
  nixpkgs.hostPlatform = "x86_64-linux";
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "antigravity"
      "code-cursor"
      "unrar"
    ];

  # Do not enable System Manager's nix module on Baguette. This host already has
  # a working multi-user Determinate Nix installation, which Home Manager can
  # use directly. Enabling the module would replace /etc/nix/nix.conf and remove
  # Determinate-specific settings such as FlakeHub and its netrc integration.

  # The pinned System Manager revision does not include Debian in its runtime
  # allow-list. Keep the distro check explicit until Debian is recognized there.
  system-manager.allowAnyDistro = true;

  # Userborn merges the declaration with the existing Debian account database.
  # Passwords remain mutable and are not declared in the Nix store. Exclude the
  # module's default root/nobody declarations so this profile owns only esko.
  services.userborn.enable = true;
  users.mutableUsers = true;
  users.users.root.enable = false;
  users.users.nobody.enable = false;

  users.groups.${username}.gid = 1000;
  users.users.${username} = {
    uid = 1000;
    isNormalUser = true;
    description = "Esko Pyyluoma";
    group = username;
    extraGroups = [ "sudo" ];
    home = homeDirectory;
    createHome = false;

    # Use Debian's shell binary so /etc/passwd never depends on a garbage-
    # collectable Nix profile path. Home Manager owns ~/.zshrc and Starship.
    shell = "/usr/bin/zsh";
  };

  # Fail safely before privileged activation if this is not the expected
  # Baguette host/account. This avoids applying the user declaration to an
  # unrelated Linux machine.
  system-manager.preActivationAssertions = {
    baguetteDistro = {
      enable = true;
      script = ''
        if [ ! -r /etc/os-release ]; then
          echo "Cannot verify the host: /etc/os-release is missing."
          exit 1
        fi

        . /etc/os-release
        if [ "''${ID:-}" != debian ] || [ "''${VERSION_CODENAME:-}" != trixie ]; then
          echo "Baguette requires Debian Trixie; found ID=''${ID:-unknown} VERSION_CODENAME=''${VERSION_CODENAME:-unknown}."
          exit 1
        fi

        actual_arch=$(/usr/bin/uname -m)
        if [ "$actual_arch" != x86_64 ]; then
          echo "Baguette requires x86_64; found $actual_arch."
          exit 1
        fi
      '';
    };

    baguetteAccount = {
      enable = true;
      script = ''
        if ! /usr/bin/id ${lib.escapeShellArg username} >/dev/null 2>&1; then
          echo "Expected existing user ${username} was not found."
          exit 1
        fi

        actual_uid=$(/usr/bin/id -u ${lib.escapeShellArg username})
        actual_gid=$(/usr/bin/id -g ${lib.escapeShellArg username})
        actual_home=$(/usr/bin/getent passwd ${lib.escapeShellArg username} | /usr/bin/cut -d: -f6)

        if [ "$actual_uid" != 1000 ] || [ "$actual_gid" != 1000 ]; then
          echo "Expected ${username} to use UID/GID 1000:1000; found $actual_uid:$actual_gid."
          exit 1
        fi

        if [ "$actual_home" != ${lib.escapeShellArg homeDirectory} ]; then
          echo "Expected ${username} home ${homeDirectory}; found $actual_home."
          exit 1
        fi
      '';
    };

    existingNix = {
      enable = true;
      script = ''
        if [ ! -x /nix/var/nix/profiles/default/bin/nix ]; then
          echo "Baguette requires the existing multi-user Determinate Nix installation."
          exit 1
        fi

        if [ ! -S /nix/var/nix/daemon-socket/socket ]; then
          echo "The Nix daemon socket is missing: /nix/var/nix/daemon-socket/socket"
          exit 1
        fi

        if [ -L /etc/nix/nix.conf ]; then
          nix_conf_target=$(/usr/bin/readlink /etc/nix/nix.conf)
          case "$nix_conf_target" in
            /nix/store/*)
              echo "/etc/nix/nix.conf still points into the Nix store: $nix_conf_target"
              echo "Restore the Determinate Nix configuration before activating Baguette."
              exit 1
              ;;
          esac
        fi
      '';
    };

    debianZsh = {
      enable = true;
      script = ''
        if [ ! -x /usr/bin/zsh ]; then
          echo "Install Debian zsh before activation: sudo apt install zsh"
          exit 1
        fi

        if ! /usr/bin/grep -qxF /usr/bin/zsh /etc/shells; then
          echo "/usr/bin/zsh must be listed in /etc/shells before activation."
          exit 1
        fi
      '';
    };
  };
}
