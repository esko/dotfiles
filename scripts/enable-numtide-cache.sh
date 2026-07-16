#!/usr/bin/env bash
# Trust Numtide's binary cache in the host-owned Determinate Nix config.
# Safe to re-run. Requires sudo. Intended for Baguette (Chromebook Debian).
set -euo pipefail

NUMTIDE_SUBSTITUTER='https://cache.numtide.com'
NUMTIDE_PUBLIC_KEY='niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g='
NIX_CONF="${NIX_CONF:-/etc/nix/nix.conf}"

if [[ "$(uname -s)" != Linux ]]; then
  printf 'This script is for Linux (Baguette). On Darwin, add the same lines to %s manually.\n' "$NIX_CONF" >&2
  exit 1
fi

if ! command -v nix >/dev/null 2>&1; then
  printf 'nix is not installed. Run scripts/bootstrap-nix.sh first.\n' >&2
  exit 1
fi

if [[ -L "$NIX_CONF" ]]; then
  target=$(readlink "$NIX_CONF")
  case "$target" in
    /nix/store/*)
      printf '%s still points into the Nix store: %s\n' "$NIX_CONF" "$target" >&2
      printf 'Restore the Determinate Nix configuration before continuing.\n' >&2
      exit 1
      ;;
  esac
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

if [[ -f "$NIX_CONF" ]]; then
  sudo cat "$NIX_CONF" >"$tmp"
else
  : >"$tmp"
fi

append_setting() {
  local key=$1
  local value=$2
  local line

  if grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "$tmp"; then
    line=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$tmp" | tail -n1)
    if printf '%s\n' "$line" | grep -Fq "$value"; then
      return 0
    fi
    # Append the value to the existing setting without dropping Determinate entries.
    awk -v key="$key" -v value="$value" '
      BEGIN { done = 0 }
      {
        if ($0 ~ "^[[:space:]]*" key "[[:space:]]*=") {
          if ($0 !~ value) {
            sub(/[[:space:]]*$/, "")
            print $0 " " value
          } else {
            print
          }
          done = 1
        } else {
          print
        }
      }
      END {
        if (!done) {
          print key " = " value
        }
      }
    ' "$tmp" >"${tmp}.new"
    mv "${tmp}.new" "$tmp"
  else
    printf '\n%s = %s\n' "$key" "$value" >>"$tmp"
  fi
}

append_setting extra-substituters "$NUMTIDE_SUBSTITUTER"
append_setting extra-trusted-public-keys "$NUMTIDE_PUBLIC_KEY"

if [[ -f "$NIX_CONF" ]] && sudo cmp -s "$tmp" "$NIX_CONF"; then
  printf 'Numtide cache already configured in %s\n' "$NIX_CONF"
else
  printf 'Updating %s\n' "$NIX_CONF"
  sudo install -m 0644 "$tmp" "$NIX_CONF"
fi

if command -v systemctl >/dev/null 2>&1; then
  printf 'Restarting nix-daemon\n'
  sudo systemctl restart nix-daemon
else
  printf 'systemctl not found; restart the Nix daemon manually.\n' >&2
fi

if nix config show 2>/dev/null | grep -Fq 'cache.numtide.com'; then
  printf 'OK: cache.numtide.com is active.\n'
  printf 'Next: cd ~/dotfiles && ./update.sh\n'
else
  printf 'Updated %s, but cache.numtide.com is not visible in `nix config show` yet.\n' "$NIX_CONF" >&2
  printf 'Open a new shell, or confirm the daemon restarted successfully.\n' >&2
  exit 1
fi
