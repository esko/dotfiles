# Dotfiles secrets

Encrypted deployment secrets live in `secrets/hosts/<deployment>.yaml` (SOPS).
Shared env secrets for all deployments live in `secrets/shared.yaml`.
Reviewable metadata and runtime mappings live in `secrets/manifest.nix`.

## Schema

Each deployment file uses this shape:

```yaml
ssh:
  id_ed25519: |-
    -----BEGIN OPENSSH PRIVATE KEY-----
    ...
    -----END OPENSSH PRIVATE KEY-----
env:
  tailscale_auth_key: tskey-auth-baguette-...
```

Shared secrets use the same `env:` section:

```yaml
env:
  tailscale_auth_key: tskey-auth-shared-...
```

- `ssh.id_ed25519` — per-deployment Ed25519 private key
- `env.<key>` — environment secrets; runtime variable names are declared in
  `secrets/manifest.nix`
- Keys listed in `shared.env` may live once in `secrets/shared.yaml` and are
  used by every deployment unless overridden in that deployment's file

Public SSH keys are stored separately in `secrets/public/<deployment>-id_ed25519.pub`.

## Bootstrap

```sh
# First-time SSH + env + update
./update.sh --target baguette --bootstrap-secrets --github
./update.sh --bootstrap-secrets --env tailscale_auth_key=tskey-auth-...

# Shared env secret for every deployment
nix run .#bootstrap-secrets -- shared-env tailscale_auth_key

# Per-deployment override
nix run .#bootstrap-secrets -- env baguette tailscale_auth_key --value 'tskey-auth-baguette-...'

# Or let it prompt for missing env values
./update.sh --synology --bootstrap-secrets
```

`./update.sh --bootstrap-secrets` creates missing SSH keys and env secrets, skips
values that already exist, and re-renders deployment env files only when the
encrypted source file changed.

Env values are resolved in this order:

1. `--env key=value` on `update.sh`
2. `secrets/shared.yaml` for keys listed in `shared.env`
3. `DOTFILES_ENV_<key>` in the environment
4. The runtime variable from `secrets/manifest.nix` (for example `TAILSCALE_AUTHKEY`)
5. An interactive prompt

At runtime and render time, per-deployment values override shared values:

1. `secrets/hosts/<deployment>.yaml`
2. `secrets/shared.yaml`

Age private identities stay host-local at `~/.config/sops/age/keys.txt`. Public
age recipients are committed under `secrets/age-recipients/<deployment>.txt`.

## Manifest (`secrets/manifest.nix`)

- `envKeys.<key>.runtime` — dotenv / environment variable name (for example `TAILSCALE_AUTHKEY`)
- `envKeys.<key>.description` — optional human-readable label for bootstrap prompts
- `shared.env` — keys that may live once in `secrets/shared.yaml`
- `consumers.<name>` — scripts that read env secrets from the encrypted file at apply time
  - `script` — filename under `scripts/`
  - `envKey` — which `env.<key>` the consumer needs
  - `hostnameAttr` — optional deployment attribute for host-specific options
  - `skipDeployments` — deployments where the consumer runs elsewhere (for example in a container)
- `deployments.<name>.env` — list of env keys stored for that host

Consumers are enabled automatically when their `envKey` appears on a deployment's
`env` list and the deployment is not in `skipDeployments`.

## Activation

Nix-managed hosts with the `sops-nix` Home Manager module decrypt secrets during
`home-manager switch`:

- SSH keys → `~/.ssh/id_ed25519`
- Env secrets → `~/.config/dotfiles/secrets/env/<key>`

`scripts/run-deployment-consumers.sh` runs enabled consumers after `./update.sh`
and Home Manager activation. Each consumer decrypts its `envKey` from the
deployment file first, then `secrets/shared.yaml`, via `sops`.

Synology and other handoff targets render dotenv files at build time:

```sh
./scripts/render-deployment-env.sh synology-dev
```

`./update.sh --synology` runs this automatically when
`secrets/hosts/synology-dev.yaml` exists.

## Adding a shared env secret

1. Declare the key in `secrets/manifest.nix` under `envKeys`
2. Add the key to `shared.env`
3. Run `nix run .#bootstrap-secrets -- shared-env <key>`

## Adding a new env secret

1. Declare the key in `secrets/manifest.nix` under `envKeys` with a `runtime` name
2. Add the key to the deployment's `env` list
3. Run `nix run .#bootstrap-secrets -- env <deployment> <key>`

## Adding a new consumer

1. Add a script under `scripts/` that reads its `envKey` via `sops_load_env_secret`
2. Register it in `secrets/manifest.nix` under `consumers`
3. Ensure the deployment's `env` list includes the consumer's `envKey`

`./update.sh` and Home Manager will run the consumer automatically when enabled.
