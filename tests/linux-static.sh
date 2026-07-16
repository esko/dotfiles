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

rg -q --fixed-strings 'https://cache.numtide.com' "$flake"
rg -q --fixed-strings 'niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=' "$flake"
rg -q 'nixConfig' "$flake"

rg -q 'hostName = "baguette"' "$flake"
rg -q 'xdg\.desktopEntries' "$linux_module"
rg -q --fixed-strings 'cursor = {' "$linux_module"
rg -q --fixed-strings 'antigravity = {' "$linux_module"
rg -q --fixed-strings 'inkscape = {' "$linux_module"
rg -q 'modules/linux/home\.nix' "$flake"
# allowUnfreePredicate must allow lib.getName "cursor" (pkgs.code-cursor).
rg -q --fixed-strings '"cursor"' "$repo_root/modules/linux/system.nix"
rg -q --fixed-strings '"cursor"' "$flake"

for token in enableHostTools enableDesktopConfigs nativeBootstrap enableGuiApps \
  code-cursor antigravity inkscape xdg.desktopEntries android-tools jdk17 vulkan-tools \
  intel-media-driver streamlink qmk; do
  rg -q --fixed-strings "$token" "$linux_module"
done

# Apt owns keyring/clipboard integration; HM must not reinstall those.
for token in wl-clipboard xclip xdotool gnome-keyring libsecret-tools p7zip; do
  if rg -q --fixed-strings "\"$token\"" "$linux_module"; then
    echo "linux module must not duplicate apt/shared package: $token" >&2
    exit 1
  fi
done

rg -q 'optional-packages\.nix' "$linux_module"

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

for token in 'Numtide binary cache' 'cache.numtide.com' './update.sh --check-only' \
  './scripts/enable-numtide-cache.sh'; do
  rg -q --fixed-strings "$token" "$bootstrap"
done

test -x "$repo_root/scripts/enable-numtide-cache.sh"
rg -q --fixed-strings 'https://cache.numtide.com' "$repo_root/scripts/enable-numtide-cache.sh"
rg -q --fixed-strings 'niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=' \
  "$repo_root/scripts/enable-numtide-cache.sh"
rg -q --fixed-strings 'nix.custom.conf' "$repo_root/scripts/enable-numtide-cache.sh"
rg -q --fixed-strings 'extra-trusted-substituters' "$repo_root/scripts/enable-numtide-cache.sh"
rg -q --fixed-strings 'nix.custom.conf' "$bootstrap"

printf '%s\n' 'linux/container static checks passed'
