#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
linux_module="$repo_root/modules/linux/home.nix"
secrets_module="$repo_root/modules/shared/secrets.nix"
container_module="$repo_root/modules/container/home.nix"
bootstrap="$repo_root/docs/linux-bootstrap.md"
flake="$repo_root/flake.nix"

for token in 'systemConfigs.baguette' 'homeConfigurations.synologyDev'; do
  rg -q --fixed-strings "$token" "$flake"
done

for token in "checks.\${linuxSystem}" 'baguette = self.systemConfigs.baguette' 'synologyDevRoot = synologyDevRoot'; do
  rg -q --fixed-strings "$token" "$flake"
done

rg -q 'hostName = "baguette"' "$flake"
rg -q 'modules/linux/home\.nix' "$flake"

for token in enableHostTools enableDesktopConfigs nativeBootstrap android-tools jdk17 vulkan-tools \
  intel-media-driver wl-clipboard xclip xdotool gnome-keyring streamlink qmk; do
  rg -q --fixed-strings "$token" "$linux_module"
done

for token in dotfiles.secrets sops.secrets ssh/id_ed25519; do
  rg -q --fixed-strings "$token" "$secrets_module"
done
rg -q --fixed-strings 'consumers' "$repo_root/secrets/manifest.nix"

for token in enableSharedTools allowGuiPackages guiPackages; do
  rg -q --fixed-strings "$token" "$container_module"
done

# Host files must be preserved; templates live below the dotfiles config dir.
if rg -q '"\.Xresources"|"\.config/weston\.ini"' "$linux_module"; then
  echo 'linux module must not overwrite active display configuration' >&2
  exit 1
fi

for token in 'non-invasive templates' 'Sommelier' 'host-owned'; do
  rg -q --fixed-strings "$token" "$bootstrap"
done

printf '%s\n' 'linux/container static checks passed'
