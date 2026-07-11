# ProxyBridge template

`ProxyBridge.defaults.json` records the reviewed non-secret settings for the
Mac Mini's ProxyBridge v3.2.0 installation:

- HTTP proxy at `synology.local:8889`
- TCP proxying for the verified Codex process names (including the app and
  helper processes listed in the JSON template)

The `protocol` and `action` values use ProxyBridge's observed enum casing
(`TCP` and `PROXY`). The JSON maps directly to the corresponding `proxyRules`
array in the app's plist defaults; it is kept separate so credentials and
machine-local plist state cannot be copied accidentally.

This is a reference template only. Home Manager does not write ProxyBridge
defaults, install the upstream signed package, or approve its system extension.
Apply it only after installing the official v3.2.0 universal package and
reviewing the process names in the app's UI/logs.

Proxy credentials, `proxyUsername`, `proxyPassword`, caches, logs, and plist
state are intentionally absent. Keep credentials in the app's secure storage
or another secret manager; never add them to this repository.
