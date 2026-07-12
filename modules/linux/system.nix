{ lib, username, homeDirectory, ... }:

{
  # Baguette is Debian Trixie running on x86_64 hardware. System Manager owns
  # only the reviewed system-level boundary; Debian still owns the kernel,
  # bootloader, hardware drivers, display manager, and apt repositories.
  nixpkgs.hostPlatform = "x86_64-linux";
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [ "unrar" ];

  # v1.1.0 predates System Manager's Debian distribution allow-list even though
  # Debian is supported. Keep the distro check explicit until the pinned release
  # includes Debian in supportedIds.
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

  # Fail safely before privileged activation if this host is not the expected
  # existing Baguette account. This avoids silently reallocating IDs or changing
  # an unrelated account on another Debian machine.
  system-manager.preActivationAssertions = {
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
