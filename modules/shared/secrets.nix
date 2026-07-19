{
  config,
  lib,
  homeDirectory,
  hostName,
  ...
}:

let
  cfg = config.dotfiles.secrets;
  manifest = import ../../secrets/manifest.nix;
  deploymentCfg =
    manifest.deployments.${hostName} or {
      ssh = false;
      env = [ ];
    };

  secretRoot = ../../secrets/hosts;
  publicRoot = ../../secrets/public;
  defaultSecretFile = secretRoot + "/${hostName}.yaml";
  defaultPublicKeyFile = publicRoot + "/${hostName}-id_ed25519.pub";
  hasDefaultSecret = builtins.pathExists defaultSecretFile;
  hasDefaultPublicKey = builtins.pathExists defaultPublicKeyFile;

  sharedEnvKeys = manifest.shared.env or [ ];
  sharedSecretFile = ../../secrets/shared.yaml;
  hasSharedSecretFile = builtins.pathExists sharedSecretFile;

  # Shared env keys are optional until secrets/shared.yaml exists. SSH-only
  # bootstrap must not require Tailscale (or other shared) material.
  declaredEnvKeys = deploymentCfg.env or [ ];
  defaultEnvKeys = lib.filter (
    key: !(lib.elem key sharedEnvKeys) || hasSharedSecretFile
  ) declaredEnvKeys;

  needsSharedEnv = builtins.any (key: lib.elem key sharedEnvKeys) declaredEnvKeys;
  needsDeploymentOnlyEnv = builtins.any (key: !lib.elem key sharedEnvKeys) declaredEnvKeys;

  sshDeployments = lib.filterAttrs (_: deployment: deployment.ssh or false) manifest.deployments;
  readPublicKey =
    name:
    let
      file = publicRoot + "/${name}-id_ed25519.pub";
    in
    if builtins.pathExists file then lib.removeSuffix "\n" (builtins.readFile file) else null;
  peerAuthorizedKeys = lib.filter (key: key != null) (
    lib.mapAttrsToList (name: _: if name == hostName then null else readPublicKey name) sshDeployments
  );
in
{
  imports = [
    ./secrets/darwin-activation.nix
    ./secrets/env.nix
    ./secrets/ssh.nix
  ];

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
        default = peerAuthorizedKeys != [ ];
        description = "Manage ~/.ssh/authorized_keys from secrets/public peer keys.";
      };

      authorizedKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = peerAuthorizedKeys;
        description = "Public keys allowed for incoming SSH connections.";
      };
    };

    env = {
      keys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = defaultEnvKeys;
        description = ''
          Environment secret keys to deploy. Shared keys from
          secrets/manifest.nix are omitted until secrets/shared.yaml exists so
          SSH-only hosts can activate without Tailscale material.
        '';
      };

      directory = lib.mkOption {
        type = lib.types.str;
        default = "${homeDirectory}/.config/dotfiles/secrets/env";
        description = "Directory for decrypted environment secret files.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    sops.defaultSopsFile = cfg.secretFile;
    sops.age.keyFile = cfg.ageKeyFile;
  };
}
