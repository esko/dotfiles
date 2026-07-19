{
  config,
  lib,
  homeDirectory,
  hostName,
  ...
}:

let
  cfg = config.dotfiles.secrets;
  manifest = import ../../../secrets/manifest.nix;
  envKeys = cfg.env.keys;
  sharedEnvKeys = manifest.shared.env or [ ];
  sharedSecretFile = ../../../secrets/shared.yaml;
  hasSharedSecretFile = builtins.pathExists sharedSecretFile;

  deploymentOnlyEnvKeys = lib.filter (key: !lib.elem key sharedEnvKeys) envKeys;
  sharedDeployedEnvKeys = lib.filter (key: lib.elem key sharedEnvKeys) envKeys;
  enabledConsumers = lib.filter (name: builtins.elem manifest.consumers.${name}.envKey envKeys) (
    lib.attrNames manifest.consumers
  );

  envSecretAttrs = lib.listToAttrs (
    map (key: {
      name = "env/${key}";
      value = {
        path = "${cfg.env.directory}/${key}";
        mode = "0400";
      };
    }) deploymentOnlyEnvKeys
  );
  sharedEnvSecretAttrs = lib.listToAttrs (
    map (key: {
      name = "env/${key}";
      value = {
        sopsFile = sharedSecretFile;
        path = "${cfg.env.directory}/${key}";
        mode = "0400";
      };
    }) sharedDeployedEnvKeys
  );
  enabled = cfg.enable && envKeys != [ ];
in
{
  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion = builtins.all (key: builtins.hasAttr key manifest.envKeys) envKeys;
          message = "Every dotfiles.secrets.env.keys entry must be declared in secrets/manifest.nix.";
        }
        {
          assertion = !enabled || deploymentOnlyEnvKeys == [ ] || builtins.pathExists cfg.secretFile;
          message = "Per-host env secrets are enabled for ${hostName} but ${toString cfg.secretFile} is missing. Run: nix run .#bootstrap-secrets -- env ${hostName} <key>";
        }
        {
          assertion = sharedDeployedEnvKeys == [ ] || hasSharedSecretFile;
          message = "Shared env keys are enabled for ${hostName} but secrets/shared.yaml is missing. Run: nix run .#bootstrap-secrets -- shared-env <key>";
        }
      ];
    }

    (lib.mkIf enabled {
      sops.secrets =
        envSecretAttrs
        // lib.optionalAttrs (hasSharedSecretFile && sharedDeployedEnvKeys != [ ]) sharedEnvSecretAttrs;

      home.file = {
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
          source = ../../../scripts/materialize-env-secret-overrides.sh;
          executable = true;
        };
      }
      // lib.optionalAttrs (enabledConsumers != [ ]) {
        ".local/bin/dotfiles-secret-consumers" = {
          source = ../../../scripts/run-deployment-consumers.sh;
          executable = true;
        };
      }
      // lib.listToAttrs (
        map (name: {
          name = ".local/bin/dotfiles-${name}";
          value = {
            source = ../../../scripts/${manifest.consumers.${name}.script};
            executable = true;
          };
        }) enabledConsumers
      );

      home.activation.dotfilesEnvSecretDirectory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD mkdir -p "${cfg.env.directory}"
        $DRY_RUN_CMD chmod 700 "${cfg.env.directory}"
      '';

      home.activation.dotfilesEnvSecretOverrides = lib.mkIf (sharedDeployedEnvKeys != [ ]) (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if [[ -x "${homeDirectory}/.local/bin/dotfiles-materialize-env-secret-overrides" ]]; then
            $DRY_RUN_CMD "${homeDirectory}/.local/bin/dotfiles-materialize-env-secret-overrides" "${hostName}" || true
          fi
        ''
      );

      home.activation.dotfilesSecretConsumers = lib.mkIf (enabledConsumers != [ ]) (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if [[ -x "${homeDirectory}/.local/bin/dotfiles-secret-consumers" ]]; then
            $DRY_RUN_CMD "${homeDirectory}/.local/bin/dotfiles-secret-consumers" "${hostName}" || true
          fi
        ''
      );
    })
  ];
}
