#!/usr/bin/env bash
# Install or update the Umans CLI into ~/.local/bin.
# Same artifact as: curl -fsSL https://api.code.umans.ai/cli/install.sh | bash
# Always uses the user prefix (never /usr/local/bin) so it matches the managed PATH.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install-umans

Install or update the Umans coding CLI (https://code.umans.ai/docs) into
~/.local/bin. Equivalent to the upstream installer, but forced to the
user-owned prefix already on PATH.
EOF
}

case "${1:-}" in
  "" ) ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  printf '%s\n' 'Do not run this installer as root or through sudo.' >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  printf '%s\n' 'curl is required.' >&2
  exit 1
fi

CLI_URL='https://api.code.umans.ai/cli/umans'
INSTALL_DIR="${HOME:?}/.local/bin"
CLI_PATH="$INSTALL_DIR/umans"

mkdir -p "$INSTALL_DIR"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

printf 'Downloading Umans CLI from %s\n' "$CLI_URL"
if ! curl -fsSL "$CLI_URL" -o "$tmp"; then
  printf '%s\n' "Failed to download $CLI_URL" >&2
  exit 1
fi

if [[ ! -s "$tmp" ]]; then
  printf '%s\n' 'Downloaded Umans CLI was empty.' >&2
  exit 1
fi

# Skip rewrite when the remote payload matches the installed file.
if [[ -f "$CLI_PATH" ]] && cmp -s "$tmp" "$CLI_PATH"; then
  printf 'Umans CLI already up to date at %s\n' "$CLI_PATH"
  exit 0
fi

install -m 0755 "$tmp" "$CLI_PATH"
printf 'Installed Umans CLI to %s\n' "$CLI_PATH"
printf 'Try: umans --help   or   umans claude\n'
