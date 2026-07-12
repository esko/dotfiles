#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
linux_module="$repo_root/modules/linux/home.nix"
linux_ssh_module="$repo_root/modules/linux/ssh.nix"
container_module="$repo_root/modules/container/home.nix"
bootstrap="$repo_root/docs/linux-bootstrap.md"
flake="$repo_root/flake.nix"

for token in 'homeConfigurations.crostini' 'homeConfigurations.baguette' 'homeConfigurations.debianTrixie'; do
  rg -q --fixed-strings "$token" "$flake"
done

rg -q 'hostName = "baguette"' "$flake"
rg -q 'modules/linux/home\.nix' "$flake"

for token in enableHostTools enableDesktopConfigs nativeBootstrap android-tools jdk17 vulkan-tools \
  intel-media-driver wl-clipboard xclip xdotool gnome-keyring streamlink qmk; do
  rg -q --fixed-strings "$token" "$linux_module"
done

for token in privateKeySecret authorizedKeys sops.secrets id_ed25519; do
  rg -q --fixed-strings "$token" "$linux_ssh_module"
done

for token in enableSharedTools allowGuiPackages guiPackages Debian Trixie Docker GUI; do
  rg -q --fixed-strings "$token" "$container_module" "$bootstrap"
done

# Host files must be preserved; templates live below the dotfiles config dir.
if rg -q '"\.Xresources"|"\.config/weston\.ini"' "$linux_module"; then
  echo 'linux module must not overwrite active display configuration' >&2
  exit 1
fi

rg -q 'Bookworm' "$bootstrap"
rg -q 'Sommelier' "$bootstrap"
rg -q 'Finansi' "$bootstrap"
rg -q 'launch wrapper' "$bootstrap"

printf '%s\n' 'linux/container static checks passed'
