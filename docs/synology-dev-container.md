# Synology development container

This repository builds `dotfiles-synology-dev:latest` as a `linux/amd64`
development image for the Synology NAS. The build follows the Nix/Dockerfile
pattern described in [Using Nix with Dockerfiles](https://mitchellh.com/writing/nix-with-dockerfiles):
Nix produces the runtime closure in a builder stage, and a `FROM scratch`
stage receives only that closure and the prepared root filesystem. Nix is not
installed in the final image.

The image contains the shared dotfiles utilities plus `pi`, `herdr`, `reasonix`,
`opencode`, `hunk`, `yazi`, `flow`, Google Antigravity CLI (`agy`), OpenAI
Codex, `mosh-server`, Eternal Terminal (`et`/`etserver`), `tailscale`, and `tsshd`. It runs
as the NAS user `1026:100`,
uses `/home/esko` as `HOME`, and opens in `/workspace`. It does not contain an
SSH server or systemd, does not request privileged mode, and should not be
given the Docker socket.

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

The remote-session server binaries are installed for explicit, per-session
use; the image does not daemonize them or add an SSH server. Mosh and tsshd are
normally launched through an existing SSH transport, while `etserver` listens
on TCP 2022 by default. Any Container Manager port mappings, DSM firewall
rules, or startup commands remain deliberate operator configuration.
With the supplied Compose file these three helpers are dormant binaries: there
is no in-container SSH transport or port mapping through which a remote client
can launch them. Making them remotely usable requires a separately reviewed
SSH/exec bridge or SSH service and explicit Container Manager/firewall ports.

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

## Build, test, and transfer

Docker must be running locally, and the `synology` SSH alias must resolve. Run:

```sh
./scripts/build-synology-dev.sh
```

The script performs the complete non-root handoff:

1. Runs `docker build --platform linux/amd64` with
   `Dockerfile.synology-dev`, tagging the result
   `dotfiles-synology-dev:latest`.
2. Runs `tests/synology-dev-runtime.sh` against the built image.
3. Uses `docker save` to create the uncompressed archive
   `dist/synology-dev/dotfiles-synology-dev-linux-amd64.tar` and generates its
   SHA-256 checksum. The archive is deliberately not gzipped because DSM's
   Container Manager import path reliably accepts a Docker `tar` archive.
4. Copies the archive, checksum, and Compose file to
   `synology:/volume3/homes/esko/dotfiles-synology-dev/`.
5. Runs `sha256sum -c` over SSH on the NAS. It does not load the image, create
   a project, or start a container.

The equivalent transfer and remote verification commands are:

```sh
ssh synology mkdir -p /volume3/homes/esko/dotfiles-synology-dev
scp -O \
  dist/synology-dev/dotfiles-synology-dev-linux-amd64.tar \
  dist/synology-dev/dotfiles-synology-dev-linux-amd64.tar.sha256 \
  compose/synology-dev.compose.yaml \
  synology:/volume3/homes/esko/dotfiles-synology-dev/
ssh synology \
  "cd /volume3/homes/esko/dotfiles-synology-dev && sha256sum -c dotfiles-synology-dev-linux-amd64.tar.sha256"
```

## Manual Container Manager installation

Importing an image and creating the project require root-backed Container
Manager operations and GUI choices, so these steps are intentionally left for
the NAS operator:

1. In Container Manager, import
   `/volume3/homes/esko/dotfiles-synology-dev/dotfiles-synology-dev-linux-amd64.tar`.
2. Create a project from `synology-dev.compose.yaml` (or the equivalent
   root-level `docker-compose.yml`).
3. Replace `/volume3/homes/esko/CHANGE_ME_WORKSPACE` with the absolute NAS path
   that should be mounted at `/workspace`.
4. Ensure `synology-dev.env` is present on the NAS (produced by `./update.sh --synology`
   after `nix run .#bootstrap-secrets -- env synology-dev tailscale_auth_key`),
   or add `TAILSCALE_AUTHKEY` manually in Container Manager.
5. Review the mounts, retain user `1026:100`, then build and start the project.

The named cache, data, and state volumes preserve mutable XDG data and shell
history across container replacement. Narrowly scoped volumes also preserve
Codex (`~/.codex`), Pi (`~/.pi`), Antigravity (`~/.gemini`), Reasonix
(`~/.reasonix`), and Tailscale (`/var/lib/tailscale`) state.
Declarative Home Manager files remain in the image, so upgrades cannot retain
symlinks to Nix-store paths from an older image. Deleting these volumes deletes
the corresponding accumulated state.

## Credentials and host configuration

No user or deployment private SSH keys, API tokens, or host credentials are
embedded in the image. Dependency source trees may contain public test
fixtures. Add only the credentials a tool needs through Container Manager
after the import. Prefer read-only bind mounts of individual files over
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
persistent named volume (XDG data/state, `~/.codex`, `~/.pi`, `~/.gemini`, or
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
  --mount type=volume,src=dotfiles-synology-dev-pi,dst=/home/esko/.pi \
  --mount type=volume,src=dotfiles-synology-dev-gemini,dst=/home/esko/.gemini \
  --mount type=volume,src=dotfiles-synology-dev-reasonix,dst=/home/esko/.reasonix \
  --mount type=bind,src=/volume3/homes/esko/CHANGE_ME_WORKSPACE,dst=/workspace \
  dotfiles-synology-dev:latest
```

This command is illustrative; use the Container Manager project for the
durable configuration.
