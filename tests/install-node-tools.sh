#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
installer="$repo_root/scripts/install-node-tools.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

make_fake_command() {
  local name=$1

  {
    printf '%s\n' '#!/usr/bin/env bash'
    cat
  } >"$tmp_dir/bin/$name"
  chmod +x "$tmp_dir/bin/$name"
}

assert_contains() {
  local haystack=$1
  local needle=$2

  if [[ "$haystack" != *"$needle"* ]]; then
    printf 'Expected output to contain: %s\nActual output:\n%s\n' "$needle" "$haystack" >&2
    return 1
  fi
}

# Write package.json bin metadata + shim bins for the managed npm set.
seed_managed_npm_tree() {
  local root=$1
  mkdir -p "$root/bin"

  write_pkg() {
    local name=$1
    local bin_json=$2
    local dir="$root/lib/node_modules/$name"
    mkdir -p "$dir"
    printf '{"name":"%s","version":"1.0.0","bin":%s}\n' "$name" "$bin_json" >"$dir/package.json"
  }

  write_pkg "agent-browser" '{"agent-browser":"./cli.js"}'
  write_pkg "@google/gemini-cli" '{"gemini":"./cli.js"}'
  write_pkg "@google/jules" '{"jules":"./cli.js"}'
  write_pkg "command-code" '{"cmd":"./cli.js","command-code":"./cli.js"}'
  write_pkg "hunkdiff" '{"hunk":"./cli.js","hunkdiff":"./cli.js"}'
  write_pkg "portless" '{"portless":"./cli.js"}'

  for command_name in agent-browser gemini jules cmd command-code hunk hunkdiff portless; do
    printf "#!/bin/bash\nexit 0\n" >"$root/bin/$command_name"
    chmod +x "$root/bin/$command_name"
  done
}

fake_npm_script() {
  cat <<'EOF'
case "${1:-}" in
  list)
    if [[ -e "${NPM_INSTALL_CALLED:-/}" || -d "$NPM_CONFIG_PREFIX/lib/node_modules" ]]; then
      pkg=""
      for arg in "$@"; do
        case "$arg" in
          --*|list) ;;
          *) pkg=$arg ;;
        esac
      done
      if [[ -n "$pkg" && -d "$NPM_CONFIG_PREFIX/lib/node_modules/$pkg" ]]; then
        printf '{"dependencies":{"%s":{"version":"1.0.0"}}}\n' "$pkg"
      elif [[ -n "$pkg" && -e "${NPM_INSTALL_CALLED:-/}" ]]; then
        printf '{"dependencies":{"%s":{"version":"1.0.0"}}}\n' "$pkg"
      else
        printf '%s\n' '{}'
      fi
    else
      printf '%s\n' '{}'
    fi
    exit 0
    ;;
  view)
    field=version
    target=""
    for arg in "$@"; do
      case "$arg" in
        view|--json) ;;
        version|bin) field=$arg ;;
        *) target=$arg ;;
      esac
    done
    name=${target%@*}
    if [[ "$field" == bin ]]; then
      case "$name" in
        command-code) printf '%s\n' '{"cmd":"./cli.js","command-code":"./cli.js"}' ;;
        hunkdiff) printf '%s\n' '{"hunk":"./cli.js","hunkdiff":"./cli.js"}' ;;
        @google/gemini-cli) printf '%s\n' '{"gemini":"./cli.js"}' ;;
        @google/jules) printf '%s\n' '{"jules":"./cli.js"}' ;;
        agent-browser) printf '%s\n' '{"agent-browser":"./cli.js"}' ;;
        portless) printf '%s\n' '{"portless":"./cli.js"}' ;;
        *) printf '{"%s":"./cli.js"}\n' "$name" ;;
      esac
    else
      printf '%s\n' '"1.0.0"'
    fi
    exit 0
    ;;
  install)
    for arg in "$@"; do
      if [[ "$arg" = --force ]]; then
        touch "$NPM_FORCE_USED"
      fi
      if [[ "$arg" = --global ]]; then
        touch "$NPM_INSTALL_CALLED"
      fi
    done
    # shellcheck disable=SC1090
    source "$SEED_MANAGED_NPM"
    seed_managed_npm_tree "$NPM_CONFIG_PREFIX"
    exit 0
    ;;
esac
exit 0
EOF
}

output=$(PATH="/usr/bin:/bin" /bin/bash "$installer" --help 2>&1)
assert_contains "$output" 'Usage: install-node-tools [--with-browser]'
assert_contains "$output" 'left untouched'

mkdir -p "$tmp_dir/bin" "$tmp_dir/home"
test_path="$tmp_dir/bin:/usr/bin:/bin"
make_fake_command node <<'EOF'
printf '%s\n' 'v23.11.0'
EOF
make_fake_command npm <<'EOF'
touch "$NPM_CALLED"
EOF

set +e
output=$(env -i HOME="$tmp_dir/home" NPM_CALLED="$tmp_dir/npm-called" PATH="$test_path" \
  /bin/bash "$installer" 2>&1)
status=$?
set -e

if [[ $status -eq 0 ]]; then
  printf '%s\n' 'Expected Node 23 to be rejected' >&2
  exit 1
fi
assert_contains "$output" 'Node.js 24 or newer is required'
if [[ -e $tmp_dir/npm-called ]]; then
  printf '%s\n' 'npm was invoked despite the incompatible Node.js version' >&2
  exit 1
fi

make_fake_command node <<'EOF'
printf '%s\n' 'v24.0.0'
EOF

# Export seed helper for the fake npm install path.
seed_helper="$tmp_dir/seed-managed-npm.sh"
{
  printf '%s\n' '#!/usr/bin/env bash'
  declare -f seed_managed_npm_tree
} >"$seed_helper"

make_fake_command npm <<EOF
$(fake_npm_script)
EOF

output=$(env -i HOME="$tmp_dir/home" NPM_FORCE_USED="$tmp_dir/npm-force-used" \
  NPM_INSTALL_CALLED="$tmp_dir/npm-install-called" \
  SEED_MANAGED_NPM="$seed_helper" PATH="$test_path" \
  /bin/bash "$installer" 2>&1)
assert_contains "$output" 'Installed npm packages:'
assert_contains "$output" 'Installed commands:'
assert_contains "$output" 'Agent CLIs (Home Manager / llm-agents.nix):'
assert_contains "$output" "$tmp_dir/home/.local/bin/portless"
assert_contains "$output" 'command-code'
assert_contains "$output" 'hunkdiff'
assert_contains "$output" 'install'
if [[ ! -e $tmp_dir/npm-force-used ]]; then
  printf '%s\n' 'Expected npm install to pass --force when packages change' >&2
  exit 1
fi
if [[ ! -e $tmp_dir/npm-install-called ]]; then
  printf '%s\n' 'Expected npm install to run for missing packages' >&2
  exit 1
fi

# Skip path: installed versions already match registry; npm install must not run.
rm -f "$tmp_dir/npm-force-used" "$tmp_dir/npm-install-called"
make_fake_command npm <<EOF
$(fake_npm_script)
EOF

seed_managed_npm_tree "$tmp_dir/home/.local"
mkdir -p "$tmp_dir/home/.agent-browser/browsers/chrome-1.0.0"

output=$(env -i HOME="$tmp_dir/home" NPM_INSTALL_CALLED="$tmp_dir/npm-install-called" \
  SEED_MANAGED_NPM="$seed_helper" PATH="$test_path" /bin/bash "$installer" 2>&1)
assert_contains "$output" 'already match the requested versions'
assert_contains "$output" 'skip'
assert_contains "$output" 'Installed commands:'
assert_contains "$output" 'command-code'
if [[ "$output" == *"managed browser runtime is not"* ]]; then
  printf '%s\n' 'browser install tip shown even though runtime exists' >&2
  exit 1
fi
if [[ -e $tmp_dir/npm-install-called ]]; then
  printf '%s\n' 'npm install ran even though versions already matched' >&2
  exit 1
fi

rm -rf "$tmp_dir/home/.local" "$tmp_dir/home/.agent-browser"
make_fake_command npm <<EOF
$(fake_npm_script)
EOF

# Install everything except portless bin to fail command verification.
make_fake_command npm <<'EOF'
case "${1:-}" in
  list)
    pkg=""
    for arg in "$@"; do
      case "$arg" in
        --*|list) ;;
        *) pkg=$arg ;;
      esac
    done
    if [[ -n "$pkg" ]]; then
      printf '{"dependencies":{"%s":{"version":"1.0.0"}}}\n' "$pkg"
    else
      printf '%s\n' '{}'
    fi
    exit 0
    ;;
  view)
    field=version
    target=""
    for arg in "$@"; do
      case "$arg" in
        view|--json) ;;
        version|bin) field=$arg ;;
        *) target=$arg ;;
      esac
    done
    name=${target%@*}
    if [[ "$field" == bin ]]; then
      case "$name" in
        command-code) printf '%s\n' '{"cmd":"./cli.js","command-code":"./cli.js"}' ;;
        hunkdiff) printf '%s\n' '{"hunk":"./cli.js","hunkdiff":"./cli.js"}' ;;
        @google/gemini-cli) printf '%s\n' '{"gemini":"./cli.js"}' ;;
        @google/jules) printf '%s\n' '{"jules":"./cli.js"}' ;;
        agent-browser) printf '%s\n' '{"agent-browser":"./cli.js"}' ;;
        portless) printf '%s\n' '{"portless":"./cli.js"}' ;;
        *) printf '{"%s":"./cli.js"}\n' "$name" ;;
      esac
    else
      printf '%s\n' '"1.0.0"'
    fi
    exit 0
    ;;
  install)
    touch "$NPM_INSTALL_CALLED"
    mkdir -p "$NPM_CONFIG_PREFIX/bin" \
      "$NPM_CONFIG_PREFIX/lib/node_modules/agent-browser" \
      "$NPM_CONFIG_PREFIX/lib/node_modules/@google/gemini-cli" \
      "$NPM_CONFIG_PREFIX/lib/node_modules/@google/jules" \
      "$NPM_CONFIG_PREFIX/lib/node_modules/command-code" \
      "$NPM_CONFIG_PREFIX/lib/node_modules/hunkdiff" \
      "$NPM_CONFIG_PREFIX/lib/node_modules/portless"
    printf '%s\n' '{"name":"agent-browser","version":"1.0.0","bin":{"agent-browser":"./cli.js"}}' \
      >"$NPM_CONFIG_PREFIX/lib/node_modules/agent-browser/package.json"
    printf '%s\n' '{"name":"@google/gemini-cli","version":"1.0.0","bin":{"gemini":"./cli.js"}}' \
      >"$NPM_CONFIG_PREFIX/lib/node_modules/@google/gemini-cli/package.json"
    printf '%s\n' '{"name":"@google/jules","version":"1.0.0","bin":{"jules":"./cli.js"}}' \
      >"$NPM_CONFIG_PREFIX/lib/node_modules/@google/jules/package.json"
    printf '%s\n' '{"name":"command-code","version":"1.0.0","bin":{"cmd":"./cli.js","command-code":"./cli.js"}}' \
      >"$NPM_CONFIG_PREFIX/lib/node_modules/command-code/package.json"
    printf '%s\n' '{"name":"hunkdiff","version":"1.0.0","bin":{"hunk":"./cli.js","hunkdiff":"./cli.js"}}' \
      >"$NPM_CONFIG_PREFIX/lib/node_modules/hunkdiff/package.json"
    printf '%s\n' '{"name":"portless","version":"1.0.0","bin":{"portless":"./cli.js"}}' \
      >"$NPM_CONFIG_PREFIX/lib/node_modules/portless/package.json"
    for command_name in agent-browser gemini jules cmd command-code hunk hunkdiff; do
      printf "#!/bin/bash\nexit 0\n" >"$NPM_CONFIG_PREFIX/bin/$command_name"
      chmod +x "$NPM_CONFIG_PREFIX/bin/$command_name"
    done
    exit 0
    ;;
esac
exit 0
EOF

set +e
output=$(env -i HOME="$tmp_dir/home" NPM_INSTALL_CALLED="$tmp_dir/npm-install-called" \
  PATH="$test_path" /bin/bash "$installer" 2>&1)
status=$?
set -e

if [[ $status -eq 0 ]]; then
  printf '%s\n' 'Expected a missing installed command to fail verification' >&2
  exit 1
fi
assert_contains "$output" 'portless        not found on PATH'

rm -rf "$tmp_dir/home/.local"
mkdir -p "$tmp_dir/home/.local/share/fnm/node-versions/v24.0.0/installation/bin"
fnm_npm_called="$tmp_dir/fnm-npm-called"
cat >"$tmp_dir/home/.local/share/fnm/node-versions/v24.0.0/installation/bin/npm" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == uninstall && ${2:-} == --global ]]; then
  touch "$FNM_NPM_CALLED"
fi
exit 0
EOF
chmod +x "$tmp_dir/home/.local/share/fnm/node-versions/v24.0.0/installation/bin/npm"

make_fake_command npm <<EOF
$(fake_npm_script)
EOF

output=$(env -i HOME="$tmp_dir/home" NPM_FORCE_USED="$tmp_dir/npm-force-used" \
  NPM_INSTALL_CALLED="$tmp_dir/npm-install-called" \
  SEED_MANAGED_NPM="$seed_helper" \
  FNM_NPM_CALLED="$fnm_npm_called" PATH="$test_path" \
  /bin/bash "$installer" 2>&1)
assert_contains "$output" 'Removing legacy fnm globals from'
if [[ ! -e $fnm_npm_called ]]; then
  printf '%s\n' 'Expected install-node-tools to uninstall legacy fnm globals' >&2
  exit 1
fi

printf '%s\n' 'install-node-tools behavior checks passed'
