# ProxyBridge template

This records the reviewed non-secret settings for the Mac Mini's ProxyBridge
installation:

- HTTP proxy at `synology.local:8889` (VPN container on the Synology)
- TCP proxying for verified agent process names:
  - Codex app/helper names listed in the JSON template
  - Grok Build CLI: `grok`, binary basename `grok-macos-aarch64`, and `Grok`
    (do not add bare `agent`; that name is reserved for Cursor Agent)

The `protocol` and `action` values use ProxyBridge's observed enum casing
(`TCP` and `PROXY`). The process, host, and port selectors are semicolon-
delimited strings, and each rule carries an explicit `enabled` boolean. This
JSON maps directly to the corresponding `proxyRules` array in the app's plist
defaults; it is kept separate so credentials and machine-local plist state
cannot be copied accidentally.

Home Manager copies this template to `~/.config/proxybridge/` but does not
install ProxyBridge or approve its Network Extension.

## Manual install on the Mini

On Apple Silicon, the Homebrew `proxybridge` cask currently ships an installer
that requires Rosetta 2:

```bash
sudo softwareupdate --install-rosetta --agree-to-license
brew install --cask proxybridge
```

After install, allow the extension in **System Settings → General → Login Items
& Extensions → Network Extension**, then import or apply these rules through
ProxyBridge's UI.

Proxy credentials, `proxyUsername`, `proxyPassword`, caches, logs, and plist
state are intentionally absent. Keep credentials in the app's secure storage
or another secret manager; never add them to this repository.
