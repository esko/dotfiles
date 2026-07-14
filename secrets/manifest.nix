# Reviewable deployment metadata. Secret values live in
# secrets/hosts/<deployment>.yaml and optionally secrets/shared.yaml (SOPS-encrypted).
#
# envKeys     — declare every env.<key> and its runtime variable name
# shared.env  — keys that may live once in secrets/shared.yaml for all deployments
# consumers   — scripts that read env secrets from the encrypted file at apply time
# deployments — per-host ssh/env lists and consumer-specific options
{
  envKeys = {
    tailscale_auth_key = {
      runtime = "TAILSCALE_AUTHKEY";
      description = "Tailscale pre-auth key for tailnet join";
    };
  };

  shared = {
    env = [ "tailscale_auth_key" ];
  };

  consumers = {
    tailscale-join = {
      script = "tailscale-join.sh";
      envKey = "tailscale_auth_key";
      hostnameAttr = "tailscaleHostname";
      skipDeployments = [ "synology-dev" ];
    };
  };

  deployments = {
    baguette = {
      ssh = true;
      env = [ "tailscale_auth_key" ];
      tailscaleHostname = "baguette";
    };
    crostini = {
      ssh = true;
      env = [ "tailscale_auth_key" ];
      tailscaleHostname = "crostini";
    };
    mini = {
      ssh = true;
      env = [ "tailscale_auth_key" ];
      tailscaleHostname = "mini";
    };
    debian-trixie = {
      ssh = false;
      env = [ ];
    };
    debian-trixie-container = {
      ssh = false;
      env = [ "tailscale_auth_key" ];
      tailscaleHostname = "debian-trixie-container";
    };
    synology-dev = {
      ssh = false;
      env = [ "tailscale_auth_key" ];
      tailscaleHostname = "synology-dev";
      renderEnvFile = "synology-dev.env";
    };
  };
}
