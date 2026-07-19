#!/usr/bin/env bash
set -euo pipefail

# Apply this repository to the current machine (or hand off the Synology image).
# Run from the dotfiles checkout: ./update.sh

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$repo_root"

TARGET_MARKER="${DOTFILES_TARGET_MARKER:-$HOME/.config/dotfiles/target}"
SYSTEM_MANAGER=""
NIX_DARWIN=""

# Numtide cache URLs (for operator messaging). Trust is host-local via
# scripts/enable-numtide-cache.sh — not client --option flags.
NUMTIDE_SUBSTITUTER='https://cache.numtide.com'
NUMTIDE_PUBLIC_KEY='niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g='
# Kept empty on purpose; see configure_nix_cache_opts.
NIX_CACHE_OPTS=()

target=""
do_pull=false
skip_node_tools=false
skip_umans=false
check_only=false
allow_builds=false
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
                      baguette, mini, synology
  --synology        Build and hand off the Synology dev image (any host with Docker)
  --pull            Run git pull --ff-only before updating
  --check-only      Run nix flake check for the current target, do not activate
  --skip-node-tools Skip install-node-tools after Home Manager activation
  --skip-umans      Skip install-umans after Home Manager activation
  --allow-builds    Allow compiling when substitutes are missing (default: refuse
                    baguette/mini updates unless cache.numtide.com is trusted)
  --bootstrap-secrets
                    Bootstrap missing SSH/env secrets and render env files when
                    the encrypted source changed. Existing values are kept.
  --env KEY=VALUE   Env secret for --bootstrap-secrets (repeatable)
  --github          When bootstrapping SSH, add the key to GitHub
  --set-origin-ssh  When bootstrapping SSH, switch origin to git@github.com
  -h, --help        Show this help

Auto-detection order:
  1. --target or ~/.config/dotfiles/target
  2. macOS            -> mini
  3. Debian Trixie    -> baguette

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
    --skip-umans)
      skip_umans=true
      shift
      ;;
    --allow-builds)
      allow_builds=true
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

# zsh (Cursor, SSH, non-login) often inherits
# __NIX_DARWIN_SET_ENVIRONMENT_DONE without a usable PATH, so nix-darwin's
# /etc/zshenv skips set-environment and Determinate's nix binary is invisible.
# Prepend the usual profile bins before any require_command / nix calls.
ensure_managed_path() {
  local path_prefix=""
  local dir
  for dir in \
    "${HOME:?}/.local/bin" \
    "${HOME}/.nix-profile/bin" \
    "/etc/profiles/per-user/${USER}/bin" \
    /run/current-system/sw/bin \
    /nix/var/nix/profiles/default/bin; do
    if [[ -d "$dir" ]]; then
      case ":${PATH}:" in
        *":${dir}:"*) ;;
        *) path_prefix+="${dir}:" ;;
      esac
    fi
  done
  if [[ -n "$path_prefix" ]]; then
    export PATH="${path_prefix}${PATH}"
  fi
}

# Resolve activation CLIs from flake.lock so update.sh cannot drift from the
# reviewed flake pins.
github_uri_from_lock() {
  local input=$1
  python3 - "$repo_root/flake.lock" "$input" <<'PY'
import json
import sys

lock_path, input_name = sys.argv[1], sys.argv[2]
node = json.load(open(lock_path))["nodes"][input_name]["locked"]
print(f"github:{node['owner']}/{node['repo']}/{node['rev']}")
PY
}

resolve_activation_pins() {
  # Run the locked system-manager package through this flake. A direct
  # `nix run github:numtide/system-manager/...` loads that flake's nixConfig and
  # spams trusted-public-keys warnings for unprivileged Determinate users.
  SYSTEM_MANAGER="$repo_root#system-manager"
  NIX_DARWIN=$(github_uri_from_lock nix-darwin)
}

numtide_cache_in_nix_config() {
  local config=""
  config=$(nix config show 2>/dev/null) || return 1
  printf '%s\n' "$config" | grep -Fq 'cache.numtide.com'
}

configure_nix_cache_opts() {
  # Leave client opts empty. Unprivileged Determinate users cannot set
  # restricted trust settings; passing them only prints warnings. Numtide must
  # be trusted in nix.custom.conf via scripts/enable-numtide-cache.sh.
  NIX_CACHE_OPTS=()
}

warn_flake_trust_spam() {
  local settings="${XDG_DATA_HOME:-$HOME/.local/share}/nix/trusted-settings.json"
  if [[ -f "$settings" ]] && grep -Eq 'trusted-public-keys|extra-trusted-public-keys' "$settings"; then
    cat >&2 <<EOF
Note: $settings still remembers flake trust keys. That re-injects
trusted-public-keys on every nix call and prints ignore-warnings for
unprivileged Determinate users. Re-run:

  ./scripts/enable-numtide-cache.sh
EOF
  fi
}

# Binary-first policy for baguette/mini: llm-agents (codex, …) must come from
# cache.numtide.com. Refuse to proceed unless that cache is trusted, unless the
# operator explicitly passes --allow-builds.
require_numtide_cache_for_binaries() {
  local resolved_target=$1

  case "$resolved_target" in
    baguette|mini) ;;
    *) return 0 ;;
  esac

  warn_flake_trust_spam

  if numtide_cache_in_nix_config; then
    printf 'Binary cache: cache.numtide.com is trusted (llm-agents will substitute).\n'
    return 0
  fi

  if "$allow_builds"; then
    cat >&2 <<'EOF'
Warning: cache.numtide.com is not trusted; --allow-builds was set, so Nix may
compile llm-agents CLIs (codex, claude, …) from source. Prefer:

  ./scripts/enable-numtide-cache.sh
EOF
    return 0
  fi

  cat >&2 <<'EOF'
Refusing to update: cache.numtide.com is not trusted, so llm-agents CLIs
(codex, claude, cursor-agent, …) cannot download prebuilt binaries.

Run once (sudo):

  ./scripts/enable-numtide-cache.sh
  nix config show | grep -F cache.numtide.com

Then re-run ./update.sh. To override and allow compiling, pass --allow-builds.
EOF
  exit 1
}

is_debian_trixie() {
  [[ -r /etc/os-release ]] || return 1
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" = debian && "${VERSION_CODENAME:-}" = trixie ]]
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
      if is_debian_trixie; then
        printf '%s\n' baguette
        return 0
      fi
      ;;
  esac

  return 1
}

normalize_target() {
  case "$1" in
    baguette|mini|synology)
      printf '%s\n' "$1"
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

  local installer=""
  if command -v install-node-tools >/dev/null 2>&1; then
    installer=$(command -v install-node-tools)
  elif [[ -x "${HOME:?}/.local/bin/install-node-tools" ]]; then
    installer="${HOME}/.local/bin/install-node-tools"
  elif [[ -x "$repo_root/scripts/install-node-tools.sh" ]]; then
    installer="$repo_root/scripts/install-node-tools.sh"
  fi

  if [[ -z "$installer" ]]; then
    printf '%s\n' 'install-node-tools not found; open a new shell after activation.' >&2
    return 0
  fi

  # Activation may have refreshed profile bins; refresh PATH in this shell.
  ensure_managed_path

  if ! command -v node >/dev/null 2>&1; then
    printf '%s\n' 'node is not available; skipping install-node-tools.' >&2
    return 0
  fi

  "$installer"
}

run_install_umans() {
  if "$skip_umans"; then
    return 0
  fi

  local installer=""
  if command -v install-umans >/dev/null 2>&1; then
    installer=$(command -v install-umans)
  elif [[ -x "${HOME:?}/.local/bin/install-umans" ]]; then
    installer="${HOME}/.local/bin/install-umans"
  elif [[ -x "$repo_root/scripts/install-umans.sh" ]]; then
    installer="$repo_root/scripts/install-umans.sh"
  fi

  if [[ -z "$installer" ]]; then
    printf '%s\n' 'install-umans not found; open a new shell after activation.' >&2
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    printf '%s\n' 'curl is not available; skipping install-umans.' >&2
    return 0
  fi

  "$installer" || printf '%s\n' 'install-umans failed; retry with install-umans.' >&2
}

flake_attr_for_target() {
  case "$1" in
    baguette) printf '%s\n' systemConfigs.baguette ;;
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

  if [[ "$resolved_target" = synology ]]; then
    printf '%s\n' 'Checking Synology remote-build context and Docker access'
    "$repo_root/scripts/build-synology-dev.sh" --check-only
    return 0
  fi

  attr=$(flake_attr_for_target "$resolved_target")
  printf 'Checking %s (%s)\n' "$resolved_target" "$attr"
  # ${arr[@]+...} keeps bash 3.2 + set -u happy when the array is empty
  # (macOS /bin/bash when PATH has not picked up a Nix bash yet).
  nix build ${NIX_CACHE_OPTS[@]+"${NIX_CACHE_OPTS[@]}"} ".#$attr" --no-link
}

apply_target() {
  local resolved_target=$1

  case "$resolved_target" in
    baguette)
      # system-manager switch builds the closure; skip a separate nix build so
      # day-to-day updates evaluate and substitute once.
      nix run ${NIX_CACHE_OPTS[@]+"${NIX_CACHE_OPTS[@]}"} "$SYSTEM_MANAGER" -- \
        switch --flake "$repo_root#baguette" --sudo
      # Ensure ChromeOS sees GUI launchers even if HM activation could not sudo
      # into /usr/local/share/applications during the switch.
      if [[ -x "$repo_root/scripts/publish-crostini-apps.sh" ]]; then
        "$repo_root/scripts/publish-crostini-apps.sh" || true
      fi
      run_install_node_tools
      run_install_umans
      ;;
    mini)
      if [[ "$(uname -s)" != Darwin ]]; then
        printf '%s\n' 'The mini profile must be applied on the Mac itself.' >&2
        exit 1
      fi
      # nix-darwin requires root for system activation (system.primaryUser era).
      # Prefer the caller's `nix` absolute path so sudo's secure_path still works.
      # -H resets HOME to /var/root; without it macOS sudo keeps HOME=/Users/...
      # and Nix warns that the directory is not owned by root.
      local nix_bin
      nix_bin=$(command -v nix)
      # Login shell is set by nix-darwin system.activationScripts.postActivation.
      sudo -H "$nix_bin" run ${NIX_CACHE_OPTS[@]+"${NIX_CACHE_OPTS[@]}"} "$NIX_DARWIN#darwin-rebuild" -- \
        switch --flake "$repo_root#mini"
      run_install_node_tools
      run_install_umans
      ;;
    synology)
      "$repo_root/scripts/build-synology-dev.sh"
      ;;
  esac
}

ensure_managed_path
require_command git
if ! command -v nix >/dev/null 2>&1; then
  cat >&2 <<'EOF'
Required command is not available: nix

update.sh prepended the usual Nix profile bins, but still could not find a nix
binary. Install or repair Determinate Nix so this exists and is executable:

  /nix/var/nix/profiles/default/bin/nix
EOF
  exit 1
fi
require_command python3
resolve_activation_pins
configure_nix_cache_opts

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

require_numtide_cache_for_binaries "$resolved_target"

if "$check_only"; then
  check_target "$resolved_target"
  printf 'Check complete for %s (no activation).\n' "$resolved_target"
  exit 0
fi

apply_target "$resolved_target"
run_deployment_consumers_for_target "$resolved_target"
printf 'Update complete for %s.\n' "$resolved_target"
