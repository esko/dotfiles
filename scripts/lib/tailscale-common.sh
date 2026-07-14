#!/usr/bin/env bash
# Shared Tailscale join helpers for native hosts and containers.

tailscale_backend_state() {
  local socket=${1:-}
  local args=()

  if [[ -n "$socket" ]]; then
    args=(--socket="$socket")
  fi

  if ! command -v tailscale >/dev/null 2>&1; then
    return 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    return 1
  fi

  tailscale "${args[@]}" status --json 2>/dev/null | jq -r '.BackendState // empty'
}

tailscale_is_running() {
  [[ "$(tailscale_backend_state "${1:-}")" == Running ]]
}

tailscale_load_auth_key() {
  local deployment=$1 env_key=$2

  if [[ -n "${TAILSCALE_AUTHKEY:-}" ]]; then
    return 0
  fi

  if [[ -z "$deployment" || -z "$env_key" ]]; then
    return 1
  fi

  if ! command -v sops >/dev/null 2>&1; then
    return 1
  fi

  if TAILSCALE_AUTHKEY=$(sops_load_env_secret "$deployment" "$env_key"); then
    export TAILSCALE_AUTHKEY
    return 0
  fi

  return 1
}

tailscale_run_up() {
  local hostname=$1
  shift

  local args=(up --hostname="$hostname")
  if [[ -n "${TAILSCALE_AUTHKEY:-}" ]]; then
    args+=(--auth-key="$TAILSCALE_AUTHKEY")
  fi
  if [[ -n "${TAILSCALE_EXTRA_ARGS:-}" ]]; then
    # shellcheck disable=SC2206
    args+=(${TAILSCALE_EXTRA_ARGS})
  fi

  if [[ $# -gt 0 ]]; then
    tailscale "$@" "${args[@]}"
  else
    case "$(uname -s)" in
      Darwin)
        tailscale "${args[@]}"
        ;;
      Linux)
        if sudo -n true 2>/dev/null; then
          sudo tailscale "${args[@]}"
        else
          sudo tailscale "${args[@]}"
        fi
        ;;
      *)
        tailscale "${args[@]}"
        ;;
    esac
  fi
}
