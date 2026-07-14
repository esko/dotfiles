{ config, lib, homeDirectory, hostName, ... }:

let
  cfg = config.dotfiles.secrets;
  manifest = import ../../secrets/manifest.nix;
  deploymentCfg = manifest.deployments.${hostName} or {
    ssh = false;
    env = [ ];
  };

  secretRoot = ../../secrets/hosts;
  publicRoot = ../../secrets/public;
  defaultSecretFile = secretRoot + "/${hostName}.yaml";
  defaultPublicKeyFile = publicRoot + "/${hostName}-id_ed25519.pub";
  hasDefaultSecret = builtins.pathExists defaultSecretFile;
  hasDefaultPublicKey = builtins.pathExists defaultPublicKeyFile;

  envKeys = cfg.env.keys;

  sharedEnvKeys = manifest.shared.env or [];
  sharedSecretFile = ../../secrets/shared.yaml;
  hasSharedSecretFile = builtins.pathExists sharedSecretFile;

  deploymentOnlyEnvKeys = lib.filter (key: !lib.elem key sharedEnvKeys) envKeys;
  sharedDeployedEnvKeys = lib.filter (key: lib.elem key sharedEnvKeys) envKeys;

  enabledConsumers = lib.filter (name:
    builtins.elem manifest.consumers.${name}.envKey envKeys
  ) (lib.attrNames manifest.consumers);

  envSecretAttrs = lib.listToAttrs (map (key: {
    name = "env/${key}";
    value = {
      path = "${homeDirectory}/.config/dotfiles/secrets/env/${key}";
      mode = "0400";
    };
  }) deploymentOnlyEnvKeys);

  sharedEnvSecretAttrs = lib.listToAttrs (map (key: {
    name = "env/${key}";
    value = {
      sopsFile = sharedSecretFile;
      path = "${homeDirectory}/.config/dotfiles/secrets/env/${key}";
      mode = "0400";
    };
  }) sharedDeployedEnvKeys);

  needsSharedEnv =
    builtins.any (key: lib.elem key sharedEnvKeys) (deploymentCfg.env or [ ]);
  needsDeploymentOnlyEnv =
    builtins.any (key: !lib.elem key sharedEnvKeys) (deploymentCfg.env or [ ]);

  sshEnabled = cfg.enable && cfg.ssh.enable;

  secretsEnabled = cfg.enable;
in
{
  options.dotfiles.secrets = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default =
        ((deploymentCfg.ssh or false) && hasDefaultSecret && hasDefaultPublicKey)
        || (needsDeploymentOnlyEnv && hasDefaultSecret)
        || (needsSharedEnv && hasSharedSecretFile);
      description = "Deploy SOPS-managed secrets for this host profile.";
    };

    secretFile = lib.mkOption {
      type = lib.types.path;
      default = defaultSecretFile;
      description = "Per-deployment SOPS file under secrets/hosts/.";
    };

    ageKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "${homeDirectory}/.config/sops/age/keys.txt";
      description = "Host-local age identity used to decrypt this deployment's SOPS file.";
    };

    ssh = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = deploymentCfg.ssh or false;
        description = "Deploy the encrypted Ed25519 SSH identity for this host.";
      };

      publicKeyFile = lib.mkOption {
        type = lib.types.path;
        default = defaultPublicKeyFile;
        description = "Per-deployment public Ed25519 key.";
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

    env = {
      keys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = deploymentCfg.env or [ ];
        description = "Environment secret keys to deploy from the env: section.";
      };

      directory = lib.mkOption {
        type = lib.types.str;
        default = "${homeDirectory}/.config/dotfiles/secrets/env";
        description = "Directory for decrypted environment secret files.";
      };
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = !secretsEnabled || !sshEnabled || builtins.pathExists cfg.secretFile;
          message =
            "dotfiles.secrets.secretFile does not exist for ${hostName}. Run: nix run .#bootstrap-secrets -- ssh ${hostName}";
        }
        {
          assertion = !secretsEnabled || !sshEnabled || builtins.pathExists cfg.ssh.publicKeyFile;
          message =
            "dotfiles.secrets.ssh.publicKeyFile does not exist for ${hostName}. Run: nix run .#bootstrap-secrets -- ssh ${hostName}";
        }
        {
          assertion =
            !cfg.ssh.manageAuthorizedKeys || cfg.ssh.authorizedKeys != [ ];
          message = "dotfiles.secrets.ssh.authorizedKeys must be non-empty when manageAuthorizedKeys is enabled.";
        }
        {
          assertion =
            builtins.all
              (key: builtins.hasAttr key manifest.envKeys)
              envKeys;
          message = "Every dotfiles.secrets.env.keys entry must be declared in secrets/manifest.nix.";
        }
        {
          assertion =
            !secretsEnabled
            || sharedDeployedEnvKeys == [ ]
            || hasSharedSecretFile;
          message =
            "Shared env secrets are declared for ${hostName} but secrets/shared.yaml is missing. Run: nix run .#bootstrap-secrets -- shared-env <key>";
        }
        {
          assertion =
            builtins.all
              (name: builtins.hasAttr name manifest.consumers)
              enabledConsumers;
          message = "Every enabled consumer must be declared in secrets/manifest.nix.";
        }
      ];
    }

    (lib.mkIf secretsEnabled {
      sops.defaultSopsFile = cfg.secretFile;
      sops.age.keyFile = cfg.ageKeyFile;

      sops.secrets =
        envSecretAttrs
        // lib.optionalAttrs (hasSharedSecretFile && sharedDeployedEnvKeys != [ ]) sharedEnvSecretAttrs
        // lib.optionalAttrs sshEnabled {
          "ssh/id_ed25519" = {
            path = "${homeDirectory}/.ssh/id_ed25519";
            mode = "0600";
          };
        };
    })

    (lib.mkIf (secretsEnabled && sshEnabled) {
      home.file.".ssh/id_ed25519.pub".source = cfg.ssh.publicKeyFile;

      home.file.".ssh/config.d/90-dotfiles-github.conf".text = ''
        # Generated by Home Manager for ${hostName}.
        Host github.com
          HostName github.com
          User git
          IdentityFile ~/.ssh/id_ed25519
          IdentitiesOnly yes
          AddKeysToAgent yes
      '';

      home.activation.dotfilesSshPermissions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD mkdir -p "$HOME/.ssh"
        $DRY_RUN_CMD chmod 700 "$HOME/.ssh"
        $DRY_RUN_CMD chmod 600 "$HOME/.ssh/id_ed25519"
        $DRY_RUN_CMD chmod 644 "$HOME/.ssh/id_ed25519.pub"
      '';
    })

    (lib.mkIf (secretsEnabled && envKeys != [ ]) {
      home.file =
        {
          ".config/dotfiles/secrets/README.md".text = ''
            # Deployment secrets

            Environment secrets for ${hostName} are decrypted by sops-nix during Home
            Manager activation. Per-deployment values live in
            secrets/hosts/${hostName}.yaml; shared values live in secrets/shared.yaml.
            See secrets/manifest.nix for runtime variable names.
          '';
        }
        // lib.optionalAttrs (sharedDeployedEnvKeys != [ ]) {
          ".local/bin/dotfiles-materialize-env-secret-overrides" = {
            source = ../../scripts/materialize-env-secret-overrides.sh;
            executable = true;
          };
        }
        // lib.optionalAttrs (enabledConsumers != [ ]) {
          ".local/bin/dotfiles-secret-consumers" = {
            source = ../../scripts/run-deployment-consumers.sh;
            executable = true;
          };
        }
        // lib.listToAttrs (map (name: {
          name = ".local/bin/dotfiles-${name}";
          value = {
            source = ../../scripts/${manifest.consumers.${name}.script};
            executable = true;
          };
        }) enabledConsumers);

      home.activation.dotfilesEnvSecretDirectory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD mkdir -p "${cfg.env.directory}"
        $DRY_RUN_CMD chmod 700 "${cfg.env.directory}"
      '';

      home.activation.dotfilesEnvSecretOverrides = lib.mkIf (sharedDeployedEnvKeys != [ ])
        (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if [[ -x "${homeDirectory}/.local/bin/dotfiles-materialize-env-secret-overrides" ]]; then
            $DRY_RUN_CMD "${homeDirectory}/.local/bin/dotfiles-materialize-env-secret-overrides" "${hostName}" || true
          fi
        '');

      home.activation.dotfilesSecretConsumers = lib.mkIf (enabledConsumers != [ ])
        (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if [[ -x "${homeDirectory}/.local/bin/dotfiles-secret-consumers" ]]; then
            $DRY_RUN_CMD "${homeDirectory}/.local/bin/dotfiles-secret-consumers" "${hostName}" || true
          fi
        '');
    })

    (lib.mkIf cfg.ssh.manageAuthorizedKeys {
      home.file.".ssh/authorized_keys".text =
        "${lib.concatStringsSep "\n" cfg.ssh.authorizedKeys}\n";
      home.activation.dotfilesAuthorizedKeysMode = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD chmod 600 "$HOME/.ssh/authorized_keys"
      '';
    })

  ];
}
