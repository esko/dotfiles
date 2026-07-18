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
# Grok Build must be proxied through the VPN container; keep Cursor's `agent` out.
jq -r '.proxyRules[0].processNames' "$root_dir/templates/proxybridge/ProxyBridge.defaults.json" | grep -q 'grok'
jq -r '.proxyRules[0].processNames' "$root_dir/templates/proxybridge/ProxyBridge.defaults.json" | grep -q 'grok-macos-aarch64'
! jq -r '.proxyRules[0].processNames' "$root_dir/templates/proxybridge/ProxyBridge.defaults.json" | grep -Eq '(^|;\s*)agent(\s*;|$)'
! grep -q 'masApps' "$root_dir/modules/darwin/system.nix"
! grep -q '"proxybridge"' "$root_dir/modules/darwin/system.nix"
grep -q 'backupFileExtension = "home-manager-backup"' "$root_dir/flake.nix"
grep -q 'nix.enable = false' "$root_dir/modules/darwin/system.nix"
grep -q 'documentation.enable = false' "$root_dir/modules/darwin/system.nix"
rg -q '4c11a945f40cdd2c74307048204b71305dffd562' "$root_dir/flake.nix"
grep -q 'postActivation.text' "$root_dir/modules/darwin/system.nix"
# nix-darwin now requires root for switch (system.primaryUser migration).
rg -q --fixed-strings 'sudo -H "$nix_bin" run' "$root_dir/update.sh"
rg -q --fixed-strings 'NIX_DARWIN#darwin-rebuild' "$root_dir/update.sh"
rg -q --fixed-strings 'system.primaryUser' "$root_dir/modules/darwin/system.nix"
grep -q '/usr/bin/chsh' "$root_dir/modules/darwin/system.nix"
grep -q 'target_shell=/bin/zsh' "$root_dir/modules/darwin/system.nix"
! grep -q 'environment.shells' "$root_dir/modules/darwin/system.nix"
grep -q '"cursor"' "$root_dir/modules/darwin/system.nix"
grep -q '"antigravity"' "$root_dir/modules/darwin/system.nix"
# Peer SSH Host blocks live in shared secrets.nix, not darwin/home.nix.
! grep -q '90-dotfiles-mini.conf' "$root_dir/modules/darwin/home.nix"
! grep -q 'launchagents-templates' "$root_dir/modules/darwin/home.nix"
# Darwin sops-nix activation workaround lives in shared secrets.nix.
rg -q --fixed-strings 'setupLaunchAgents' "$root_dir/modules/shared/secrets.nix"
rg -q --fixed-strings 'Mic92/sops-nix#910' "$root_dir/modules/shared/secrets.nix"
# Homebrew remains on HM sessionPath for brew-only tools (et, tsshd, …).
rg -q --fixed-strings '/opt/homebrew/bin' "$root_dir/modules/darwin/home.nix"
# mosh-server is Nix-managed on Mini so non-login remote mosh always finds it.
rg -q --fixed-strings 'mosh-server' "$root_dir/modules/darwin/home.nix"
rg -q --fixed-strings 'mosh' "$root_dir/modules/shared/home.nix"
! rg -q '"mosh"' "$root_dir/modules/darwin/system.nix"
for plist in "$root_dir"/templates/launchagents/*.plist; do
  grep -q '<key>Disabled</key>' "$plist"
  grep -q '<true/>' "$plist"
done

echo "Darwin static checks passed"
