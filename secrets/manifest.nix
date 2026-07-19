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
      # How other hosts address this machine over SSH / Tailscale MagicDNS.
      sshHostName = "baguette";
      sshAliases = [ "baguette.local" ];
      env = [ "tailscale_auth_key" ];
      tailscaleHostname = "baguette";
    };
    mini = {
      ssh = true;
      sshHostName = "mini";
      sshAliases = [
        "macmini"
        "mini.local"
      ];
      env = [ "tailscale_auth_key" ];
      tailscaleHostname = "mini";
    };
    synology-dev = {
      ssh = false;
      env = [ "tailscale_auth_key" ];
      tailscaleHostname = "synology-dev";
      renderEnvFile = "synology-dev.env";
    };
  };
}
