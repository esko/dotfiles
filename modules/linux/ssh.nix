{ config, lib, username, homeDirectory, ... }:

let
  cfg = config.dotfiles.linux.ssh;
in
{
  options.dotfiles.linux.ssh = {
    enable = lib.mkEnableOption "the encrypted Crostini Ed25519 SSH key";

    privateKeySecret = lib.mkOption {
      type = lib.types.str;
      default = "ssh/crostini/id_ed25519";
      description = "sops-nix secret name containing the Crostini Ed25519 private key.";
    };

    publicKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional Crostini public key text.";
    };

    manageAuthorizedKeys = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Explicitly opt in to managing incoming SSH authorization.";
    };

    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Public keys allowed for incoming SSH connections.";
    };
  };

  config = {
    assertions = [
      {
        assertion = !cfg.manageAuthorizedKeys || cfg.authorizedKeys != [ ];
        message = "dotfiles.linux.ssh.authorizedKeys must be non-empty when manageAuthorizedKeys is enabled.";
      }
    ];

    sops.secrets = lib.mkIf cfg.enable {
      "${cfg.privateKeySecret}" = {
        path = "${homeDirectory}/.ssh/id_ed25519";
        mode = "0600";
      };
    };

    home.file.".ssh/id_ed25519.pub" = lib.mkIf (cfg.publicKey != null) {
      text = "${cfg.publicKey}\n";
    };

    home.file.".ssh/authorized_keys" = lib.mkIf cfg.manageAuthorizedKeys {
      text = "${lib.concatStringsSep "\n" cfg.authorizedKeys}\n";
    };

    home.activation.dotfilesAuthorizedKeysMode = lib.mkIf cfg.manageAuthorizedKeys
      (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD chmod 600 "$HOME/.ssh/authorized_keys"
      '');
  };
}
