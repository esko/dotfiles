# Synology development container

This repository builds `dotfiles-synology-dev:latest` as a `linux/amd64`
development image for the Synology NAS. The build follows the Nix/Dockerfile
pattern described in [Using Nix with Dockerfiles](https://mitchellh.com/writing/nix-with-dockerfiles):
Nix produces the runtime closure in a builder stage, and a `FROM scratch`
stage receives only that closure and the prepared root filesystem. Nix is not
installed in the final image.

The image contains the shared dotfiles utilities plus `pi`, `herdr`, `reasonix`,
`opencode`, `hunk`, `yazi`, `flow`, Google Antigravity CLI (`agy`), Grok Build
(`grok`), OpenAI Codex, `mosh-server`, Eternal Terminal (`et`/`etserver`),
`tailscale`, `tsshd`, OpenSSH, and fail2ban. The image's default shell runs as
the NAS user `1026:100`, uses `/home/esko` as `HOME`, and opens in `/workspace`.
The supplied Compose project starts as root so it can initialize Tailscale,
host SSH keys, fail2ban, and `sshd`; remote logins are restricted to `esko` and
use public-key authentication. It does not use systemd or privileged mode and
must not be given the Docker socket.

The agent CLIs are pinned through
[`llm-agents.nix`](https://github.com/numtide/llm-agents.nix). OpenCode is an
intentional exception to that flake's regular x64 release asset: its source is
overridden with the upstream `opencode-linux-x64-baseline` archive. The
ordinary nixpkgs source build also omits OpenCode's `--baseline` build flag, so
using it would not establish compatibility with the NAS's non-AVX2 Intel
J3455. The exact baseline 1.17.18 payload was executed on the target NAS as a
compatibility check.
The root-only Docker builder trusts Numtide's published binary cache so its
pinned daily builds are substituted instead of compiling every agent locally.

The supplied Compose command joins Tailscale and then runs `sshd` on port 2222.
The macvlan address exposes that port directly rather than through a Docker
port mapping. Mosh, tsshd, and `etserver` remain available for explicit use;
their additional DSM firewall ports and startup remain operator choices.

## Tailscale inside the container

Tailscale runs inside the container, not on the Synology host. The image ships
`tailscaled` and a boot script that joins the tailnet before SSH starts. The
Compose file grants `NET_ADMIN`, `NET_RAW`, and `/dev/net/tun`, and persists
Tailscale identity in the `dotfiles-synology-dev-tailscale` volume at
`/var/lib/tailscale`.

Set a reusable auth key in Container Manager when creating the project:

```yaml
environment:
  TAILSCALE_AUTHKEY: tskey-auth-...
```

### Automated auth key handoff

Store the Tailscale auth key in the unified secrets file, then update:

```sh
nix run .#bootstrap-secrets -- env synology-dev tailscale_auth_key
git add secrets/hosts/synology-dev.yaml secrets/age-recipients/synology-dev.txt .sops.yaml
./update.sh --synology
```

`./update.sh --synology` builds the image, runs `render-deployment-env.sh`, and
writes `synology-dev.env` when
`secrets/hosts/synology-dev.yaml` exists, and copies the handoff bundle to the NAS.

Create the auth key in the Tailscale admin console as **Reusable** (optionally
tagged and expiring). After the first successful join, the
`dotfiles-synology-dev-tailscale` volume keeps node identity; later container
recreates rejoin without consuming another key.

Optional overrides:

- `TAILSCALE_HOSTNAME` (default `synology-dev`)
- `TAILSCALE_EXTRA_ARGS` (extra flags passed to `tailscale up`, for example
  `--advertise-tags=tag:container`)
- `TAILSCALE_AUTHKEY_FILE` (read the key from a bind-mounted file instead of
  the environment)
- `TAILSCALE_SOCKET` (default `/var/run/tailscale/tailscaled.sock`)

After SSHing in, inspect the node with:

```sh
tailscale --socket="$TAILSCALE_SOCKET" status
```

The macvlan LAN address (`192.168.1.252`) and the Tailscale address coexist.
Use the tailnet IP or MagicDNS name for mesh access; keep the macvlan mapping
for local LAN services such as noVNC.

## Build and test on Synology

The Mac only prepares a filtered source archive and streams it over SSH. Docker
and Colima are not required locally. The `synology` SSH alias must resolve, the
remote account must have passwordless `sudo -n` access to
`/usr/local/bin/docker`, and the NAS must have enough free space for the Nix
builder layers. DSM's Docker package omits Buildx, so the script installs the
official Buildx v0.11.2 Linux AMD64 plugin under the handoff directory after
verifying its pinned SHA-256 checksum. Run:

```sh
ssh synology 'sudo -n /usr/local/bin/docker info >/dev/null'
./scripts/build-synology-dev.sh --check-only
./scripts/build-synology-dev.sh
```

`--check-only` validates the filtered context and remote passwordless Docker
access without starting the heavy image build.
The equivalent top-level check is `./update.sh --synology --check-only`.

The script:

1. Enumerates tracked and non-ignored working-tree files, applies
   `.dockerignore`, and independently rejects secret and identity paths.
2. Streams the temporary compressed context to `synology`; it does not leave a
   source checkout or context archive on the NAS.
3. Runs `docker build` with BuildKit and `Dockerfile.synology-dev` on the NAS as
   root, producing the local image `dotfiles-synology-dev:latest` without an
   image archive or Container Manager import.
4. Copies the Compose definition, startup scripts, runtime test, and optional
   `synology-dev.env` to `/volume3/homes/esko/dotfiles-synology-dev/`.
5. Runs `tests/synology-dev-runtime.sh` through the remote Docker daemon.

The script does not create, start, or recreate the Container Manager project.
An older `dotfiles-synology-dev-linux-amd64.tar` from the previous workflow can
be removed manually after the remote build has been verified.

## Manual Container Manager project update

The remote build makes the image immediately visible to Container Manager.
Project creation and replacement remain deliberate NAS operator actions:

1. Create or update a project from `synology-dev.compose.yaml` (or the equivalent
   root-level `docker-compose.yml`).
2. Replace `/volume3/homes/esko/CHANGE_ME_WORKSPACE` with the absolute NAS path
   that should be mounted at `/workspace`.
3. Ensure `synology-dev.env` is present on the NAS (produced by `./update.sh --synology`
   after `nix run .#bootstrap-secrets -- env synology-dev tailscale_auth_key`),
   or add `TAILSCALE_AUTHKEY` manually in Container Manager.
4. Verify that the external `mymacvlan` and `macvlan_bridge` networks exist and
   that `192.168.1.252` is available.
5. Review the root startup boundary and read-only SSH mount, then recreate or
   start the project so it uses the newly built image.

The named cache, data, and state volumes preserve mutable XDG data and shell
history across container replacement. Narrowly scoped volumes also preserve
Codex (`~/.codex`), Grok Build (`~/.grok`), Pi (`~/.pi`), Antigravity (`~/.gemini`), Reasonix
(`~/.reasonix`), and Tailscale (`/var/lib/tailscale`) state.
Declarative Home Manager files remain in the image, so upgrades cannot retain
symlinks to Nix-store paths from an older image. Deleting these volumes deletes
the corresponding accumulated state.

The entrypoint refreshes Grok Build's non-secret `~/.grok/config.toml` from the
image on every start so an older named volume cannot mask configuration updates.
Supply LiteLLM virtual keys through `synology-dev.env` or the persistent
`~/.local/state/grok-litellm-harness/virtual-keys.env`; never add them to the
tracked TOML file.

## Credentials and host configuration

No user or deployment private SSH keys, API tokens, or host credentials are
embedded in the image. Dependency source trees may contain public test
fixtures. Add only the credentials a tool needs through Container Manager.
Prefer read-only bind mounts of individual files over
mounting an entire host home, for example:

```yaml
services:
  dev:
    volumes:
      - /volume3/homes/esko/.ssh:/home/esko/.ssh:ro
      - /volume3/homes/esko/.config/opencode:/home/esko/.config/opencode:ro
```

Mounting `.ssh` read-only allows outbound Git/SSH use without letting the
container alter the host's keys or `known_hosts`. If a CLI needs to update its
configuration or token cache, copy just that configuration into its matching
persistent named volume (XDG data/state, `~/.codex`, `~/.grok`, `~/.pi`, `~/.gemini`, or
`~/.reasonix`) instead of changing the image. Do not bind mount `/var/run/docker.sock`, and do
not enable privileged mode.

## Agent desktop and browser automation

The container bundles [agent-workspace-linux](https://github.com/agent-sh/agent-workspace-linux),
not [computer-use-linux](https://github.com/agent-sh/computer-use-linux). The
distinction matters:

- `computer-use-linux` drives the **host's real desktop** through AT-SPI and
  session portals.
- `agent-workspace-linux` gives agents an **isolated hidden X11 workspace**
  (Xvfb + Openbox + workspace-owned Chromium) over MCP, without touching your
  laptop or NAS desktop.

After SSHing in, verify the runtime:

```sh
agent-workspace-linux doctor
```

Create a workspace explicitly, then launch the browser profile:

```sh
agent-workspace-linux workspace start \
  --ack-hidden-workspace \
  --purpose "Synology QA"

agent-workspace-linux workspace launch \
  --name browser \
  --profile browser-session \
  -- chromium
```

Agents can drive the workspace through MCP. Register the stdio server from
`config/synology-dev/codex-mcp-workspace.toml`, or run:

```sh
agent-workspace-linux mcp
```

Visual debugging options on the LAN:

- Screenshots: `agent-workspace-linux workspace observe --screenshot --output /tmp/ws.png`
- Live view: after a workspace is running, attach noVNC against its display:

```sh
DISPLAY=:99 synology-dev-workspace-novnc
```

Then open `http://192.168.1.252:6080/vnc.html` in a browser.

Browser automation uses the workspace-owned Chromium DevTools endpoint on
loopback inside the container. Pair it with `agent-browser --cdp 9222` or the
`agent-workspace-linux` browser MCP tools.

## Direct smoke run

After the image has been imported manually, an optional terminal smoke test on
the NAS is:

```sh
/usr/local/bin/docker run --rm -it \
  --user 1026:100 \
  --mount type=volume,src=dotfiles-synology-dev-cache,dst=/home/esko/.cache \
  --mount type=volume,src=dotfiles-synology-dev-data,dst=/home/esko/.local/share \
  --mount type=volume,src=dotfiles-synology-dev-state,dst=/home/esko/.local/state \
  --mount type=volume,src=dotfiles-synology-dev-codex,dst=/home/esko/.codex \
  --mount type=volume,src=dotfiles-synology-dev-grok,dst=/home/esko/.grok \
  --mount type=volume,src=dotfiles-synology-dev-pi,dst=/home/esko/.pi \
  --mount type=volume,src=dotfiles-synology-dev-gemini,dst=/home/esko/.gemini \
  --mount type=volume,src=dotfiles-synology-dev-reasonix,dst=/home/esko/.reasonix \
  --mount type=bind,src=/volume3/homes/esko/CHANGE_ME_WORKSPACE,dst=/workspace \
  dotfiles-synology-dev:latest
```

This command is illustrative; use the Container Manager project for the
durable configuration.
