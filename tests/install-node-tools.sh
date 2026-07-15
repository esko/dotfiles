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

  if [[ $haystack != *"$needle"* ]]; then
    printf 'Expected output to contain: %s\nActual output:\n%s\n' "$needle" "$haystack" >&2
    return 1
  fi
}

output=$(PATH="/usr/bin:/bin" /bin/bash "$installer" --help 2>&1)
assert_contains "$output" 'Usage: install-node-tools [--with-browser]'

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
make_fake_command npm <<'EOF'
for arg in "$@"; do
  if [[ "$arg" = --force ]]; then
    touch "$NPM_FORCE_USED"
  fi
done
for command_name in agent-browser gemini jules cmd hunk portless; do
  printf "#!/bin/bash\nexit 0\n" >"$NPM_CONFIG_PREFIX/bin/$command_name"
  chmod +x "$NPM_CONFIG_PREFIX/bin/$command_name"
done
EOF

output=$(env -i HOME="$tmp_dir/home" NPM_FORCE_USED="$tmp_dir/npm-force-used" PATH="$test_path" \
  /bin/bash "$installer" 2>&1)
assert_contains "$output" 'Installed commands:'
assert_contains "$output" "$tmp_dir/home/.local/bin/portless"
if [[ ! -e $tmp_dir/npm-force-used ]]; then
  printf '%s\n' 'Expected npm install to pass --force for existing global bins' >&2
  exit 1
fi

rm -rf "$tmp_dir/home/.local"
make_fake_command npm <<'EOF'
for command_name in agent-browser gemini jules cmd hunk; do
  printf "#!/bin/bash\nexit 0\n" >"$NPM_CONFIG_PREFIX/bin/$command_name"
  chmod +x "$NPM_CONFIG_PREFIX/bin/$command_name"
done
EOF

set +e
output=$(env -i HOME="$tmp_dir/home" PATH="$test_path" /bin/bash "$installer" 2>&1)
status=$?
set -e

if [[ $status -eq 0 ]]; then
  printf '%s\n' 'Expected a missing installed command to fail verification' >&2
  exit 1
fi
assert_contains "$output" 'portless        not found on PATH'

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

make_fake_command npm <<'EOF'
for arg in "$@"; do
  if [[ "$arg" = --force ]]; then
    touch "$NPM_FORCE_USED"
  fi
done
for command_name in agent-browser gemini jules cmd hunk portless; do
  printf "#!/bin/bash\nexit 0\n" >"$NPM_CONFIG_PREFIX/bin/$command_name"
  chmod +x "$NPM_CONFIG_PREFIX/bin/$command_name"
done
EOF

output=$(env -i HOME="$tmp_dir/home" NPM_FORCE_USED="$tmp_dir/npm-force-used" \
  FNM_NPM_CALLED="$fnm_npm_called" PATH="$test_path" \
  /bin/bash "$installer" 2>&1)
assert_contains "$output" 'Removing legacy fnm globals from'
if [[ ! -e $fnm_npm_called ]]; then
  printf '%s\n' 'Expected install-node-tools to uninstall legacy fnm globals' >&2
  exit 1
fi

printf '%s\n' 'install-node-tools behavior checks passed'
