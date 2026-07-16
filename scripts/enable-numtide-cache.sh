#!/usr/bin/env bash
# Trust Numtide's binary cache in the host-owned Determinate Nix config.
# Safe to re-run. Requires sudo. Intended for Baguette (Chromebook Debian).
#
# Determinate Nix regenerates /etc/nix/nix.conf. Custom settings must go in
# /etc/nix/nix.custom.conf (included via !include). Writing to nix.conf alone
# is overwritten and never sticks.
set -euo pipefail

NUMTIDE_SUBSTITUTER='https://cache.numtide.com'
NUMTIDE_PUBLIC_KEY='niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g='
NIX_DIR="${NIX_DIR:-/etc/nix}"
NIX_CONF="${NIX_CONF:-$NIX_DIR/nix.conf}"
# Determinate's supported customization seam.
NIX_CUSTOM_CONF="${NIX_CUSTOM_CONF:-$NIX_DIR/nix.custom.conf}"

if [[ "$(uname -s)" != Linux ]]; then
  printf 'This script is for Linux (Baguette). On Darwin, add the same lines to %s manually.\n' "$NIX_CUSTOM_CONF" >&2
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

if [[ -f "$NIX_CONF" ]] && ! grep -Eq '^[[:space:]]*!include[[:space:]]+nix\.custom\.conf[[:space:]]*$' "$NIX_CONF" \
  && ! grep -Eq '^[[:space:]]*!include[[:space:]]+.*/nix\.custom\.conf[[:space:]]*$' "$NIX_CONF"; then
  printf 'warning: %s does not !include nix.custom.conf\n' "$NIX_CONF" >&2
  printf 'Determinate Nix normally includes it. Continuing with %s anyway.\n' "$NIX_CUSTOM_CONF" >&2
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

if [[ -f "$NIX_CUSTOM_CONF" ]]; then
  sudo cat "$NIX_CUSTOM_CONF" >"$tmp"
else
  cat >"$tmp" <<'EOF'
# Managed by scripts/enable-numtide-cache.sh (dotfiles).
# Determinate Nix loads this file from /etc/nix/nix.conf via !include.
EOF
fi

append_setting() {
  local key=$1
  local value=$2

  if grep -Eq "^[[:space:]]*${key}[[:space:]]*=" "$tmp"; then
    if grep -E "^[[:space:]]*${key}[[:space:]]*=" "$tmp" | grep -Fq "$value"; then
      return 0
    fi
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

# extra-substituters: use the cache by default.
# extra-trusted-substituters: let non-trusted users (typical Determinate
#   trusted-users = root) actually consume it.
# extra-trusted-public-keys: verify NarInfo signatures from Numtide.
# accept-flake-config = false: do not re-apply flake nixConfig trust keys as
#   client settings (that is what reprints trusted-public-keys warnings).
append_setting extra-substituters "$NUMTIDE_SUBSTITUTER"
append_setting extra-trusted-substituters "$NUMTIDE_SUBSTITUTER"
append_setting extra-trusted-public-keys "$NUMTIDE_PUBLIC_KEY"
append_setting accept-flake-config false

# Previously-accepted flake nixConfig (from llm-agents / system-manager, or an
# older `nix run github:numtide/system-manager`) is stored in trusted-settings.json
# and re-injected on every nix invocation as client-specified trusted-public-keys,
# which unprivileged users cannot set — hence the warning spam during update.sh.
clear_flake_trust_spam() {
  local settings="${XDG_DATA_HOME:-$HOME/.local/share}/nix/trusted-settings.json"
  [[ -f "$settings" ]] || return 0

  python3 - "$settings" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
try:
    data = json.loads(path.read_text())
except Exception:
    sys.exit(0)

if not isinstance(data, dict):
    sys.exit(0)

# Restricted trust settings must live in nix.custom.conf, not as remembered
# client flake approvals.
removed = []
for key in (
    "trusted-public-keys",
    "extra-trusted-public-keys",
    "trusted-substituters",
    "extra-trusted-substituters",
    "substituters",
    "extra-substituters",
):
    if key in data:
        removed.append(key)
        del data[key]

if not removed:
    sys.exit(0)

backup = path.with_suffix(".json.bak.dotfiles")
backup.write_text(path.read_text())
path.write_text(json.dumps(data, indent=2) + "\n")
print(f"Cleared flake trust spam from {path} (backup: {backup})")
print("Removed keys: " + ", ".join(removed))
PY
}

clear_flake_trust_spam

if [[ -f "$NIX_CUSTOM_CONF" ]] && sudo cmp -s "$tmp" "$NIX_CUSTOM_CONF"; then
  printf 'Numtide cache already configured in %s\n' "$NIX_CUSTOM_CONF"
else
  printf 'Updating %s\n' "$NIX_CUSTOM_CONF"
  sudo install -m 0644 "$tmp" "$NIX_CUSTOM_CONF"
fi

# Drop stale copies from nix.conf if a previous script revision wrote there.
# Determinate owns that file; leave a note only when we remove Numtide lines.
if [[ -f "$NIX_CONF" ]] && sudo grep -Fq 'cache.numtide.com' "$NIX_CONF"; then
  printf 'Removing stale cache.numtide.com entries from Determinate-managed %s\n' "$NIX_CONF"
  sudo cp "$NIX_CONF" "${NIX_CONF}.bak.dotfiles"
  sudo awk '
    /cache\.numtide\.com/ { next }
    /niks3\.numtide\.com-1:/ { next }
    { print }
  ' "$NIX_CONF" | sudo tee "${NIX_CONF}.tmp" >/dev/null
  sudo mv "${NIX_CONF}.tmp" "$NIX_CONF"
  printf 'Backup: %s.bak.dotfiles\n' "$NIX_CONF"
fi

if command -v systemctl >/dev/null 2>&1; then
  printf 'Restarting nix-daemon\n'
  if systemctl list-unit-files nix-daemon.service >/dev/null 2>&1; then
    sudo systemctl restart nix-daemon
  elif systemctl list-unit-files determinate-nixd.socket >/dev/null 2>&1; then
    sudo systemctl restart determinate-nixd.socket
  else
    sudo systemctl restart nix-daemon 2>/dev/null \
      || sudo systemctl restart determinate-nixd 2>/dev/null \
      || printf 'Could not restart a known Nix daemon unit; restart it manually.\n' >&2
  fi
else
  printf 'systemctl not found; restart the Nix daemon manually.\n' >&2
fi

config=$(nix config show 2>/dev/null || true)
ok=true
for needle in \
  'cache.numtide.com' \
  'niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g='; do
  if ! printf '%s\n' "$config" | grep -Fq "$needle"; then
    ok=false
    printf 'missing from `nix config show`: %s\n' "$needle" >&2
  fi
done

if "$ok"; then
  printf 'OK: Numtide cache is active via %s\n' "$NIX_CUSTOM_CONF"
  printf 'Next: cd ~/dotfiles && ./update.sh\n'
else
  printf 'Updated %s, but Numtide settings are not visible in `nix config show` yet.\n' "$NIX_CUSTOM_CONF" >&2
  printf 'Confirm %s contains !include nix.custom.conf and the daemon restarted.\n' "$NIX_CONF" >&2
  exit 1
fi
