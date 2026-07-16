#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install-node-tools [--with-browser]

Install or update the shared Node-based CLI tools from their published npm
packages into the user-owned npm prefix. Packages already present at the
requested version are left untouched (no re-download).

Options:
  --with-browser  Also download the browser runtime used by agent-browser.
  -h, --help      Show this help.
EOF
}

with_browser=false
case "${1:-}" in
  "")
    ;;
  --with-browser)
    with_browser=true
    ;;
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
  printf '%s\n' "Do not run this installer as root or through sudo." >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  printf '%s\n' "npm is required. Activate the Home Manager profile first." >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  printf '%s\n' "Node.js 24 or newer is required. Activate the Home Manager profile first." >&2
  exit 1
fi

node_version=$(node --version 2>/dev/null || true)
node_major=${node_version#v}
node_major=${node_major%%.*}
if [[ ! $node_major =~ ^[0-9]+$ || $node_major -lt 24 ]]; then
  printf 'Node.js 24 or newer is required; active version is %s.\n' "${node_version:-unknown}" >&2
  exit 1
fi

prefix="${NPM_CONFIG_PREFIX:-$HOME/.local}"
export NPM_CONFIG_PREFIX="$prefix"
export PATH="$prefix/bin:$PATH"
mkdir -p "$prefix/bin"

packages=(
  "agent-browser@latest"
  "@google/gemini-cli@latest"
  "@google/jules@latest"
  "command-code@latest"
  "hunkdiff@latest"
  "portless@latest"
)

managed_packages=()
for package_spec in "${packages[@]}"; do
  managed_packages+=("${package_spec%@*}")
done

package_name() {
  # @scope/name@tag -> @scope/name; name@tag -> name
  printf '%s\n' "${1%@*}"
}

package_requested_ref() {
  local spec=$1 name
  name=$(package_name "$spec")
  printf '%s\n' "${spec#"${name}"@}"
}

installed_package_version() {
  local name=$1
  # npm list exits non-zero when the package is missing; ignore that.
  npm list --global --depth=0 --json "$name" 2>/dev/null \
    | python3 -c '
import json, sys
name = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
dep = (data.get("dependencies") or {}).get(name) or {}
sys.stdout.write(dep.get("version") or "")
' "$name"
}

resolved_package_version() {
  local name=$1 ref=$2
  # Prefer an exact view of name@ref so tags and pinned versions both work.
  npm view "${name}@${ref}" version --json 2>/dev/null \
    | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if isinstance(data, str):
    sys.stdout.write(data)
elif isinstance(data, list) and data and isinstance(data[0], str):
    sys.stdout.write(data[0])
'
}

# Every executable name published by an installed package's `bin` field.
package_bin_commands() {
  local name=$1 version=${2:-} pkg_json bin_json

  pkg_json="$prefix/lib/node_modules/$name/package.json"
  if [[ -f "$pkg_json" ]]; then
    python3 -c '
import json, sys
name = sys.argv[1]
with open(sys.argv[2], encoding="utf-8") as fh:
    data = json.load(fh)
bin_field = data.get("bin")
if isinstance(bin_field, str):
    print(name)
elif isinstance(bin_field, dict):
    for command_name in sorted(bin_field):
        print(command_name)
' "$name" "$pkg_json"
    return 0
  fi

  if [[ -n "$version" ]]; then
    bin_json=$(npm view "${name}@${version}" bin --json 2>/dev/null || true)
  else
    bin_json=$(npm view "$name" bin --json 2>/dev/null || true)
  fi
  [[ -n "$bin_json" ]] || return 0
  printf '%s' "$bin_json" | python3 -c '
import json, sys
name = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if isinstance(data, str):
    print(name)
elif isinstance(data, dict):
    for command_name in sorted(data):
        print(command_name)
' "$name"
}

remove_legacy_fnm_globals() {
  local fnm_versions_dir="${HOME}/.local/share/fnm/node-versions"
  [[ -d "$fnm_versions_dir" ]] || return 0

  local install_dir npm_bin
  for install_dir in "$fnm_versions_dir"/*/installation; do
    [[ -d "$install_dir" ]] || continue
    npm_bin="${install_dir}/bin/npm"
    [[ -x "$npm_bin" ]] || continue

    printf 'Removing legacy fnm globals from %s\n' "$install_dir"
    # Pre-Nix manual installs lived in fnm's default npm prefix. Uninstall them
    # so fnm's multishell PATH cannot shadow ~/.local/bin after updates.
    set +e
    env -u NPM_CONFIG_PREFIX PATH="${install_dir}/bin:${PATH}" \
      "$npm_bin" uninstall --global --no-audit --no-fund "${managed_packages[@]}" >/dev/null 2>&1
    set -e
  done
}

printf 'Installing Node CLI packages into %s\n' "$prefix"
remove_legacy_fnm_globals

packages_to_install=()
for package_spec in "${packages[@]}"; do
  name=$(package_name "$package_spec")
  ref=$(package_requested_ref "$package_spec")
  installed=$(installed_package_version "$name" || true)
  desired=$(resolved_package_version "$name" "$ref" || true)

  if [[ -n "$installed" && -n "$desired" && "$installed" == "$desired" ]]; then
    printf '  skip %-28s %s (already installed)\n' "$name" "$installed"
    continue
  fi

  if [[ -n "$installed" && -n "$desired" ]]; then
    printf '  update %-26s %s -> %s\n' "$name" "$installed" "$desired"
  elif [[ -n "$desired" ]]; then
    printf '  install %-25s %s\n' "$name" "$desired"
  else
    # Registry lookup failed; fall back to npm install for this spec.
    printf '  install %-25s %s (version lookup unavailable)\n' "$name" "$ref"
  fi
  packages_to_install+=("$package_spec")
done

if [[ ${#packages_to_install[@]} -eq 0 ]]; then
  printf 'All Node CLI packages already match the requested versions.\n'
else
  # --force replaces existing global bins when a package actually changes.
  npm install --global --force --no-audit --no-fund "${packages_to_install[@]}"
fi

browser_runtime_present() {
  # Chrome for Testing lands under ~/.agent-browser/browsers after
  # `agent-browser install`. Existing Chrome/Brave/Puppeteer installs also work,
  # but this is the path the managed download uses.
  local browser_dir="${AGENT_BROWSER_HOME:-$HOME/.agent-browser}/browsers"
  [[ -d "$browser_dir" ]] || return 1
  # Any chrome-* tree counts as an installed managed runtime.
  compgen -G "$browser_dir"/chrome-* >/dev/null 2>&1
}

if "$with_browser"; then
  if browser_runtime_present; then
    printf 'agent-browser runtime already present; skipping download.\n'
  elif [[ "$(uname -s)" == Linux ]]; then
    agent-browser install --with-deps
  else
    agent-browser install
  fi
elif ! browser_runtime_present; then
  cat <<'EOF'

The agent-browser CLI is installed, but its managed browser runtime is not.
Download it with:
  agent-browser install
On a fresh Debian host with missing browser libraries:
  agent-browser install --with-deps
Or re-run: install-node-tools --with-browser
EOF
fi

report_command() {
  local command_name=$1
  if command -v "$command_name" >/dev/null 2>&1; then
    printf '  %-15s %s\n' "$command_name" "$(command -v "$command_name")"
    return 0
  fi
  printf '  %-15s %s\n' "$command_name" "not found on PATH"
  return 1
}

printf '\nInstalled npm packages:\n'
missing_packages=0
declare -a installed_commands=()
for package_spec in "${packages[@]}"; do
  name=$(package_name "$package_spec")
  installed=$(installed_package_version "$name" || true)
  if [[ -n "$installed" ]]; then
    printf '  %-28s %s\n' "$name" "$installed"
    while IFS= read -r command_name; do
      [[ -n "$command_name" ]] || continue
      installed_commands+=("$command_name")
    done < <(package_bin_commands "$name" "$installed")
  else
    printf '  %-28s %s\n' "$name" "not installed"
    missing_packages=$((missing_packages + 1))
  fi
done

printf '\nInstalled commands:\n'
missing_commands=0
if [[ ${#installed_commands[@]} -eq 0 ]]; then
  printf '  (none)\n'
  missing_commands=1
else
  # Unique + sorted so packages that share bins do not print twice.
  while IFS= read -r command_name; do
    [[ -n "$command_name" ]] || continue
    if ! report_command "$command_name"; then
      missing_commands=$((missing_commands + 1))
    fi
  done < <(printf '%s\n' "${installed_commands[@]}" | sort -u)
fi

printf '\nAgent CLIs (Home Manager / llm-agents.nix):\n'
missing_agents=0
for command_name in agent agy claude codex grok pi; do
  if ! report_command "$command_name"; then
    missing_agents=$((missing_agents + 1))
  fi
done

if [[ $missing_packages -ne 0 || $missing_commands -ne 0 ]]; then
  printf '\nInstallation verification failed: %d package(s), %d command(s) missing.\n' \
    "$missing_packages" "$missing_commands" >&2
  exit 1
fi

if [[ $missing_agents -ne 0 ]]; then
  cat >&2 <<EOF

Note: $missing_agents agent CLI(s) from llm-agents.nix are not on PATH.
They are installed by Home Manager, not this npm installer. Re-run:
  ./update.sh
EOF
fi
