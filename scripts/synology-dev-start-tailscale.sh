#!/usr/bin/env bash
set -euo pipefail

state_dir=${SYNOLOGY_DEV_TAILSCALE_STATE_DIR:-/var/lib/tailscale}
socket=${TAILSCALE_SOCKET:-/var/run/tailscale/tailscaled.sock}
hostname=${TAILSCALE_HOSTNAME:-synology-dev}

load_auth_key() {
  if [[ -n "${TAILSCALE_AUTHKEY:-}" ]]; then
    return 0
  fi

  if [[ -n "${TAILSCALE_AUTHKEY_FILE:-}" && -f "$TAILSCALE_AUTHKEY_FILE" ]]; then
    TAILSCALE_AUTHKEY=$(<"$TAILSCALE_AUTHKEY_FILE")
    export TAILSCALE_AUTHKEY
  fi
}

mkdir -p "$state_dir" "$(dirname "$socket")"

if [[ ! -c /dev/net/tun ]]; then
  mkdir -p /dev/net
  if [[ ! -c /dev/net/tun ]]; then
    mknod /dev/net/tun c 10 200
    chmod 0666 /dev/net/tun
  fi
fi

if [[ ! -S "$socket" ]]; then
  tailscaled --statedir="$state_dir" --socket="$socket" &
  for _ in $(seq 1 60); do
    if [[ -S "$socket" ]]; then
      break
    fi
    sleep 0.5
  done
fi

if [[ ! -S "$socket" ]]; then
  printf '%s\n' 'tailscaled did not create its control socket' >&2
  exit 1
fi

backend_state=
if command -v jq >/dev/null 2>&1; then
  backend_state=$(
    tailscale --socket="$socket" status --json 2>/dev/null \
      | jq -r '.BackendState // empty' \
      || true
  )
fi

if [[ "$backend_state" == Running ]]; then
  tailscale --socket="$socket" status
  exit 0
fi

load_auth_key

args=(--socket="$socket" up --hostname="$hostname")
if [[ -n "${TAILSCALE_AUTHKEY:-}" ]]; then
  args+=(--auth-key="$TAILSCALE_AUTHKEY")
fi
if [[ -n "${TAILSCALE_EXTRA_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  args+=(${TAILSCALE_EXTRA_ARGS})
fi

if tailscale "${args[@]}"; then
  tailscale --socket="$socket" status
  exit 0
fi

printf '%s\n' \
  'Tailscale did not join the tailnet.' \
  'First boot: run ./update.sh --synology --bootstrap-secrets,' \
  'rebuild with ./scripts/build-synology-dev.sh,' \
  'or set TAILSCALE_AUTHKEY / TAILSCALE_AUTHKEY_FILE in the container environment.' \
  >&2
exit 1
