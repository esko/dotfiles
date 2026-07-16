#!/usr/bin/env bash
set -euo pipefail

image=${1:-dotfiles-synology-dev:latest}

if ! command -v docker >/dev/null 2>&1; then
  echo 'docker is required for Synology dev-container runtime checks' >&2
  exit 1
fi

if ! docker image inspect "$image" >/dev/null 2>&1; then
  printf 'Docker image is not available: %s\n' "$image" >&2
  exit 1
fi

platform=$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$image")
if [[ "$platform" != 'linux/amd64' ]]; then
  printf 'expected linux/amd64 image, got %s\n' "$platform" >&2
  exit 1
fi

docker run --rm --entrypoint /bin/zsh "$image" -lc '
  set -eu

  test "$(id -u)" = 1026
  test "$(id -g)" = 100
  test "$HOME" = /home/esko
  test "$(pwd)" = /workspace
  test "$OPENCODE_DISABLE_AUTOUPDATE" = true
  test -x /lib64/ld-linux-x86-64.so.2

  workspace_probe="/workspace/.dotfiles-write-test-$$"
  : > "$workspace_probe"
  rm -f "$workspace_probe"

  passwd_shell=$(
    while IFS=: read -r account _ _ _ _ _ login_shell; do
      if [[ "$account" = esko ]]; then
        printf "%s\\n" "$login_shell"
        break
      fi
    done </etc/passwd
  )
  test "$passwd_shell" = /bin/zsh
  /bin/zsh -lic '\''test "$ZSH_NAME" = zsh'\''

  for command_name in \
    pi herdr reasonix opencode hunk yazi flow \
    mosh-server etserver tailscale tailscaled tsshd agy grok codex bun \
    synology-dev-start-tailscale synology-dev-start-services \
    agent-workspace-linux Xvfb xdotool chromium \
    git rg fd jq zellij starship; do
    command -v "$command_name" >/dev/null
  done

  pi --version >/dev/null
  herdr --version >/dev/null
  reasonix --version >/dev/null
  cpu_model=""
  while IFS= read -r cpu_line; do
    if [[ "$cpu_line" = "model name"* ]]; then
      cpu_model="${cpu_line#*: }"
      break
    fi
  done </proc/cpuinfo
  if [[ "$cpu_model" = *"QEMU TCG"* ]]; then
    printf "Skipping OpenCode execution under incompatible QEMU TCG emulation\\n"
  else
    test "$(opencode --version)" = 1.17.18
  fi
  hunk --version >/dev/null
  yazi --version >/dev/null
  flow --version >/dev/null
  mosh-server --version >/dev/null
  etserver --version >/dev/null
  tailscale version >/dev/null
  tsshd --version >/dev/null
  agy --version >/dev/null
  grok --version >/dev/null
  codex --version >/dev/null
  bun --version >/dev/null
  agent-workspace-linux doctor >/dev/null

  for config_file in \
    "$HOME/.zshrc" \
    "$HOME/.config/starship.toml" \
    "$HOME/.config/zellij/config.kdl" \
    "$HOME/.config/bat/config"; do
    test -f "$config_file"
  done

  if test -d "$HOME/.ssh"; then
    while IFS= read -r key_file; do
      case "$key_file" in
        *.pub|*/authorized_keys|*/known_hosts|*/known_hosts.old|*/config)
          continue
          ;;
      esac
      case "${key_file##*/}" in
        id_*)
          printf "private SSH key-like file is present: %s\n" "$key_file" >&2
          exit 1
          ;;
      esac
      if grep -Eq -- "-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----" "$key_file"; then
        printf "private SSH key material is present: %s\n" "$key_file" >&2
        exit 1
      fi
    done < <(find "$HOME/.ssh" -type f -print)
  fi
'

state_volume="synology-dev-runtime-state-$$"
codex_volume="synology-dev-runtime-codex-$$"
pi_volume="synology-dev-runtime-pi-$$"
gemini_volume="synology-dev-runtime-gemini-$$"
reasonix_volume="synology-dev-runtime-reasonix-$$"
cleanup_state_volume() {
  docker volume rm --force \
    "$state_volume" "$codex_volume" "$pi_volume" "$gemini_volume" "$reasonix_volume" \
    >/dev/null 2>&1 || true
}
trap cleanup_state_volume EXIT
for volume in "$state_volume" "$codex_volume" "$pi_volume" "$gemini_volume" "$reasonix_volume"; do
  docker volume create "$volume" >/dev/null
done

docker run --rm \
  --mount "type=volume,src=$state_volume,dst=/home/esko/.local/state" \
  --mount "type=volume,src=$codex_volume,dst=/home/esko/.codex" \
  --mount "type=volume,src=$pi_volume,dst=/home/esko/.pi" \
  --mount "type=volume,src=$gemini_volume,dst=/home/esko/.gemini" \
  --mount "type=volume,src=$reasonix_volume,dst=/home/esko/.reasonix" \
  --entrypoint /bin/zsh \
  "$image" -lc '
    test -f "$HOME/.zshrc"
    mkdir -p "$HOME/.local/state/zsh"
    : > "$HOME/.local/state/zsh/upgrade-probe"
    : > "$HOME/.codex/upgrade-probe"
    : > "$HOME/.pi/upgrade-probe"
    : > "$HOME/.gemini/upgrade-probe"
    : > "$HOME/.reasonix/upgrade-probe"
  '

docker run --rm \
  --mount "type=volume,src=$state_volume,dst=/home/esko/.local/state" \
  --mount "type=volume,src=$codex_volume,dst=/home/esko/.codex" \
  --mount "type=volume,src=$pi_volume,dst=/home/esko/.pi" \
  --mount "type=volume,src=$gemini_volume,dst=/home/esko/.gemini" \
  --mount "type=volume,src=$reasonix_volume,dst=/home/esko/.reasonix" \
  --entrypoint /bin/zsh \
  "$image" -lc '
    test -f "$HOME/.zshrc"
    test -f "$HOME/.local/state/zsh/upgrade-probe"
    test -f "$HOME/.codex/upgrade-probe"
    test -f "$HOME/.pi/upgrade-probe"
    test -f "$HOME/.gemini/upgrade-probe"
    test -f "$HOME/.reasonix/upgrade-probe"
  '

cleanup_state_volume
trap - EXIT

printf 'Synology dev-container runtime checks passed: %s\n' "$image"
