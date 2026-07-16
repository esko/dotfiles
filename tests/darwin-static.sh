#!/bin/sh

set -eu

root_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

for template in \
  templates/launchagents/ai.agentcli.litellm.plist \
  templates/launchagents/com.esko.llama-server.plist \
  templates/proxybridge/ProxyBridge.defaults.json \
  templates/proxybridge/README.md; do
  test -f "$root_dir/$template"
done

if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$root_dir"/templates/launchagents/*.plist
elif command -v perl >/dev/null 2>&1 && perl -MXML::Parser -e 1 >/dev/null 2>&1; then
  perl -MXML::Parser -e 'for (@ARGV) { XML::Parser->new->parsefile($_) }' \
    "$root_dir"/templates/launchagents/*.plist
else
  echo "darwin-static: no plutil or Perl XML::Parser; skipped plist parse" >&2
fi

jq empty "$root_dir/templates/proxybridge/ProxyBridge.defaults.json"
grep -q '"protocol": "TCP"' "$root_dir/templates/proxybridge/ProxyBridge.defaults.json"
grep -q '"action": "PROXY"' "$root_dir/templates/proxybridge/ProxyBridge.defaults.json"
jq -e '.proxyRules[0].processNames | type == "string"' "$root_dir/templates/proxybridge/ProxyBridge.defaults.json" >/dev/null
jq -e '.proxyRules[0].enabled == true' "$root_dir/templates/proxybridge/ProxyBridge.defaults.json" >/dev/null
! grep -q 'masApps' "$root_dir/modules/darwin/system.nix"
! grep -q '"proxybridge"' "$root_dir/modules/darwin/system.nix"
grep -q 'backupFileExtension = "home-manager-backup"' "$root_dir/flake.nix"
grep -q 'nix.enable = false' "$root_dir/modules/darwin/system.nix"
grep -q 'documentation.enable = false' "$root_dir/modules/darwin/system.nix"
rg -q '4c11a945f40cdd2c74307048204b71305dffd562' "$root_dir/flake.nix"
grep -q 'postActivation.text' "$root_dir/modules/darwin/system.nix"
! grep -q 'sudo nix run "$NIX_DARWIN#darwin-rebuild"' "$root_dir/update.sh"
grep -q '/usr/bin/chsh' "$root_dir/modules/darwin/system.nix"
grep -q 'target_shell=/bin/zsh' "$root_dir/modules/darwin/system.nix"
! grep -q 'environment.shells' "$root_dir/modules/darwin/system.nix"
grep -q '"cursor"' "$root_dir/modules/darwin/system.nix"
grep -q '"antigravity"' "$root_dir/modules/darwin/system.nix"
# Peer SSH Host blocks live in shared secrets.nix, not darwin/home.nix.
! grep -q '90-dotfiles-mini.conf' "$root_dir/modules/darwin/home.nix"
! grep -q 'launchagents-templates' "$root_dir/modules/darwin/home.nix"
for plist in "$root_dir"/templates/launchagents/*.plist; do
  grep -q '<key>Disabled</key>' "$plist"
  grep -q '<true/>' "$plist"
done

echo "Darwin static checks passed"
