#!/usr/bin/env bash
set -euo pipefail

# Apply this repository to the current machine (or hand off the Synology image).
# Run from the dotfiles checkout: ./update.sh

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$repo_root"

SYSTEM_MANAGER='github:numtide/system-manager/96f724be6f1411286e8ad0202e3e624c10116a6d'
TARGET_MARKER="${DOTFILES_TARGET_MARKER:-$HOME/.config/dotfiles/target}"

target=""
do_pull=false
skip_node_tools=false
check_only=false
synology_handoff=false
bootstrap_secrets=false
bootstrap_github=false
bootstrap_set_origin_ssh=false
declare -a bootstrap_env_overrides=()

usage() {
  cat <<'EOF'
Usage: ./update.sh [options]

Detect the current platform and apply the matching Nix profile. This is the
single entry point for day-to-day dotfiles updates.

Options:
  --target NAME     Force a profile instead of auto-detection:
                      crostini, baguette, debian-trixie,
                      debian-trixie-container, mini, synology
  --synology        Build and hand off the Synology dev image (any host with Docker)
  --pull            Run git pull --ff-only before updating
  --check-only      Run nix flake check for the current target, do not activate
  --skip-node-tools Skip install-node-tools after Home Manager activation
  --bootstrap-secrets
                    Bootstrap missing SSH/env secrets and render env files when
                    the encrypted source changed. Existing values are kept.
  --env KEY=VALUE   Env secret for --bootstrap-secrets (repeatable)
  --github          When bootstrapping SSH, add the key to GitHub
  --set-origin-ssh  When bootstrapping SSH, switch origin to git@github.com
  -h, --help        Show this help

Auto-detection order:
  1. --target or ~/.config/dotfiles/target
  2. macOS                        -> mini
  3. ChromeOS / Crostini          -> crostini
  4. Debian Trixie + hostname     -> baguette
  5. Debian Trixie + systemd PID1 -> debian-trixie-container
  6. Debian Trixie + container    -> debian-trixie

Examples:
  ./update.sh
  ./update.sh --pull
  ./update.sh --target baguette
  ./update.sh --synology
  ./update.sh --bootstrap-secrets --github
  ./update.sh --bootstrap-secrets --env tailscale_auth_key=tskey-auth-...
EOF
}

while (($#)); do
  case "$1" in
    --target)
      target=${2:-}
      shift 2
      ;;
    --synology)
      synology_handoff=true
      shift
      ;;
    --pull)
      do_pull=true
      shift
      ;;
    --check-only)
      check_only=true
      shift
      ;;
    --skip-node-tools)
      skip_node_tools=true
      shift
      ;;
    --bootstrap-secrets)
      bootstrap_secrets=true
      shift
      ;;
    --env)
      bootstrap_env_overrides+=("${2:-}")
      shift 2
      ;;
    --github)
      bootstrap_github=true
      shift
      ;;
    --set-origin-ssh)
      bootstrap_set_origin_ssh=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Required command is not available: %s\n' "$1" >&2
    exit 1
  fi
}

is_debian_trixie() {
  [[ -r /etc/os-release ]] || return 1
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" = debian && "${VERSION_CODENAME:-}" = trixie ]]
}

is_crostini() {
  [[ -f /etc/chrome_os-version ]] \
    || [[ -n "${CHROMEOS_CONTAINER:-}" ]] \
    || [[ -n "${CROS_CONTAINER_NAME:-}" ]] \
    || command -v sommelier >/dev/null 2>&1
}

is_container() {
  [[ -f /.dockerenv || -f /run/.containerenv ]]
}

is_systemd_host() {
  local init_comm=""
  [[ -r /proc/1/comm ]] || return 1
  IFS= read -r init_comm < /proc/1/comm
  [[ "$init_comm" = systemd ]]
}

hostname_short() {
  hostname -s 2>/dev/null || hostname
}

detect_target() {
  if [[ -n "$target" ]]; then
    printf '%s\n' "$target"
    return 0
  fi

  if [[ -f "$TARGET_MARKER" ]]; then
    tr -d '[:space:]' <"$TARGET_MARKER"
    return 0
  fi

  case "$(uname -s)" in
    Darwin)
      printf '%s\n' mini
      return 0
      ;;
    Linux)
      if is_crostini; then
        printf '%s\n' crostini
        return 0
      fi

      if is_debian_trixie; then
        if [[ "$(hostname_short)" = baguette ]]; then
          printf '%s\n' baguette
          return 0
        fi
        if is_systemd_host; then
          printf '%s\n' debian-trixie-container
          return 0
        fi
        if is_container; then
          printf '%s\n' debian-trixie
          return 0
        fi
        printf '%s\n' baguette
        return 0
      fi

      if is_container; then
        printf '%s\n' debian-trixie
        return 0
      fi
      ;;
  esac

  return 1
}

normalize_target() {
  case "$1" in
    crostini|baguette|debian-trixie|debian-trixie-container|mini|synology)
      printf '%s\n' "$1"
      ;;
    debianTrixie)
      printf '%s\n' debian-trixie
      ;;
    debianTrixieContainer)
      printf '%s\n' debian-trixie-container
      ;;
    *)
      printf 'Unknown target: %s\n' "$1" >&2
      exit 2
      ;;
  esac
}

save_target_marker() {
  local resolved_target=$1
  mkdir -p "$(dirname "$TARGET_MARKER")"
  printf '%s\n' "$resolved_target" >"$TARGET_MARKER"
}

run_install_node_tools() {
  if "$skip_node_tools"; then
    return 0
  fi
  if ! command -v install-node-tools >/dev/null 2>&1; then
    printf '%s\n' 'install-node-tools is not on PATH yet; open a new shell after activation.' >&2
    return 0
  fi
  if ! command -v node >/dev/null 2>&1; then
    printf '%s\n' 'node is not available; skipping install-node-tools.' >&2
    return 0
  fi
  install-node-tools
}

flake_attr_for_target() {
  case "$1" in
    crostini) printf '%s\n' homeConfigurations.crostini ;;
    baguette) printf '%s\n' systemConfigs.baguette ;;
    debian-trixie) printf '%s\n' homeConfigurations.debianTrixie ;;
    debian-trixie-container) printf '%s\n' systemConfigs.debianTrixieContainer ;;
    mini) printf '%s\n' darwinConfigurations.mini.system ;;
    synology) printf '%s\n' packages.x86_64-linux.synologyDevRoot ;;
  esac
}

deployment_for_target() {
  case "$1" in
    synology) printf '%s\n' synology-dev ;;
    *) printf '%s\n' "$1" ;;
  esac
}

sync_secrets_for_target() {
  local resolved_target=$1
  local deployment sync_args=("$repo_root/scripts/sync-deployment-secrets.sh")

  deployment=$(deployment_for_target "$resolved_target")
  sync_args+=("$deployment")

  if "$bootstrap_secrets"; then
    sync_args+=(--bootstrap)
    if "$bootstrap_github"; then
      sync_args+=(--github)
    fi
    if "$bootstrap_set_origin_ssh"; then
      sync_args+=(--set-origin-ssh)
    fi
    for env_override in "${bootstrap_env_overrides[@]}"; do
      sync_args+=(--env "$env_override")
    done
  fi

  "${sync_args[@]}"
}

run_deployment_consumers_for_target() {
  local resolved_target=$1
  local deployment

  deployment=$(deployment_for_target "$resolved_target")
  if [[ -x "$repo_root/scripts/run-deployment-consumers.sh" ]]; then
    "$repo_root/scripts/run-deployment-consumers.sh" "$deployment"
  fi
}

check_target() {
  local resolved_target=$1
  local attr
  attr=$(flake_attr_for_target "$resolved_target")
  printf 'Checking %s (%s)\n' "$resolved_target" "$attr"
  if [[ "$resolved_target" = mini ]]; then
    nix build ".#$attr" --no-link
  elif [[ "$resolved_target" = synology ]]; then
    nix build ".#$attr" --no-link
  elif [[ "$resolved_target" = baguette || "$resolved_target" = debian-trixie-container ]]; then
    nix build ".#$attr" --no-link
  else
    nix build ".#${attr}.activationPackage" --no-link
  fi
}

apply_target() {
  local resolved_target=$1

  case "$resolved_target" in
    crostini)
      nix run home-manager -- switch --flake "$repo_root#crostini"
      run_install_node_tools
      ;;
    baguette)
      nix run "$SYSTEM_MANAGER" -- switch --flake "$repo_root#baguette" --sudo
      run_install_node_tools
      ;;
    debian-trixie)
      nix run home-manager -- switch --flake "$repo_root#debianTrixie"
      run_install_node_tools
      ;;
    debian-trixie-container)
      nix run "$SYSTEM_MANAGER" -- switch --flake "$repo_root#debianTrixieContainer" --sudo
      run_install_node_tools
      ;;
    mini)
      if [[ "$(uname -s)" != Darwin ]]; then
        printf '%s\n' 'The mini profile must be applied on the Mac itself.' >&2
        exit 1
      fi
      sudo darwin-rebuild switch --flake "$repo_root#mini"
      ;;
    synology)
      "$repo_root/scripts/build-synology-dev.sh"
      ;;
  esac
}

require_command git
require_command nix

if "$do_pull"; then
  printf 'Pulling latest changes\n'
  git pull --ff-only
fi

if "$synology_handoff"; then
  target=synology
fi

if ! detected=$(detect_target); then
  cat >&2 <<'EOF'
Could not detect which dotfiles profile to apply.

Set the target once:
  ./update.sh --target crostini
  ./update.sh --target baguette
  ./update.sh --target mini

Or write ~/.config/dotfiles/target manually.
EOF
  exit 1
fi

resolved_target=$(normalize_target "$detected")
printf 'Dotfiles target: %s\n' "$resolved_target"

if [[ -n "$target" ]]; then
  save_target_marker "$resolved_target"
fi

if "$bootstrap_secrets"; then
  sync_secrets_for_target "$resolved_target"
fi

check_target "$resolved_target"

if "$check_only"; then
  printf 'Check complete for %s (no activation).\n' "$resolved_target"
  exit 0
fi

apply_target "$resolved_target"
run_deployment_consumers_for_target "$resolved_target"
printf 'Update complete for %s.\n' "$resolved_target"
