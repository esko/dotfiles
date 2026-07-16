#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
linux_module="$repo_root/modules/linux/home.nix"
secrets_module="$repo_root/modules/shared/secrets.nix"
container_module="$repo_root/modules/container/home.nix"
bootstrap="$repo_root/docs/linux-bootstrap.md"
flake="$repo_root/flake.nix"
update="$repo_root/update.sh"

for token in 'systemConfigs.baguette' 'homeConfigurations.synologyDev'; do
  rg -q --fixed-strings "$token" "$flake"
done

for token in "checks.\${linuxSystem}" 'baguette = self.systemConfigs.baguette' 'synologyDevRoot = synologyDevRoot'; do
  rg -q --fixed-strings "$token" "$flake"
done

# Cache trust belongs in nix.custom.conf, not flake nixConfig (untrusted-user warnings).
if rg -q '^[[:space:]]*nixConfig[[:space:]]*=' "$flake"; then
  echo 'flake.nix must not set nixConfig trusted-public-keys for Determinate hosts' >&2
  exit 1
fi
rg -q --fixed-strings 'https://cache.numtide.com' "$repo_root/scripts/enable-numtide-cache.sh"
rg -q --fixed-strings 'niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=' \
  "$repo_root/scripts/enable-numtide-cache.sh"
# apps.<system> must be one attrset (separate dynamic assignments collide).
rg -q -U 'apps = \{[\s\S]*bootstrap-secrets[\s\S]*bootstrap-ssh' "$flake"
rg -q --fixed-strings 'system-manager = {' "$flake"
rg -q --fixed-strings 'system-manager.packages.${linuxSystem}.default' "$flake"

rg -q 'hostName = "baguette"' "$flake"
rg -q 'xdg\.desktopEntries' "$linux_module"
rg -q --fixed-strings 'cros-garcon.service.d/override.conf' "$linux_module"
rg -q --fixed-strings 'XDG_DATA_DIRS' "$linux_module"
rg -q --fixed-strings 'publishBaguetteDesktopEntries' "$linux_module"
rg -q --fixed-strings '%h/.nix-profile/share' "$linux_module"
rg -q --fixed-strings 'publish-crostini-apps.sh' "$linux_module"
rg -q --fixed-strings 'crostini-launchers.nix' "$flake"
rg -q --fixed-strings '/usr/local/share/applications' \
  "$repo_root/modules/linux/crostini-launchers.nix"
rg -q --fixed-strings 'publish-crostini-apps.sh' "$update"
test -x "$repo_root/scripts/publish-crostini-apps.sh"
rg -q --fixed-strings 'cursor = {' "$linux_module"
rg -q --fixed-strings 'antigravity = {' "$linux_module"
rg -q --fixed-strings 'inkscape = {' "$linux_module"
rg -q --fixed-strings 'inkscape-beta = {' "$linux_module"
rg -q --fixed-strings 'Inkscape 1.5 Beta' "$linux_module"
rg -q --fixed-strings 'inkscapeStable' "$linux_module"
rg -q --fixed-strings 'inkscapeDev' "$linux_module"
rg -q 'inkscape-beta\.nix' "$flake"
rg -q --fixed-strings 'inkscapeBeta' "$flake"
test -f "$repo_root/packages/inkscape-beta.nix"
rg -q --fixed-strings '1.5.0-dev' "$repo_root/packages/inkscape-beta.nix"
rg -q --fixed-strings 'pname = "inkscape-beta"' "$repo_root/packages/inkscape-beta.nix"
rg -q --fixed-strings 'wrapGAppsHook3' "$repo_root/packages/inkscape-beta.nix"
rg -q --fixed-strings 'extraPkgs' "$repo_root/packages/inkscape-beta.nix"
rg -q --fixed-strings 'gdk-pixbuf' "$repo_root/packages/inkscape-beta.nix"
rg -q --fixed-strings 'GDK_PIXBUF_MODULE_FILE' "$repo_root/packages/inkscape-beta.nix"
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
rg -q --fixed-strings 'accept-flake-config' "$repo_root/scripts/enable-numtide-cache.sh"
rg -q --fixed-strings 'clear_flake_trust_spam' "$repo_root/scripts/enable-numtide-cache.sh"
rg -q --fixed-strings 'trusted-settings.json' "$repo_root/scripts/enable-numtide-cache.sh"
rg -q --fixed-strings 'nix.custom.conf' "$bootstrap"
rg -q --fixed-strings 'trusted-settings.json' "$update"

printf '%s\n' 'linux/container static checks passed'
