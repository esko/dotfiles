#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
image='dotfiles-synology-dev:latest'
platform='linux/amd64'
remote='synology'
remote_docker='/usr/local/bin/docker'
remote_dir='/volume3/homes/esko/dotfiles-synology-dev'
remote_docker_config="$remote_dir/docker-config"
buildx_version='v0.11.2'
buildx_asset="buildx-${buildx_version}.linux-amd64"
buildx_url="https://github.com/docker/buildx/releases/download/${buildx_version}/${buildx_asset}"
buildx_sha256='311568ee69715abc46163fd688e56c77ab0144ff32e116d0f293bfc3470e75b7'
compose="$repo_root/compose/synology-dev.compose.yaml"
dockerignore="$repo_root/.dockerignore"
check_only=false

while (($#)); do
  case "$1" in
    --check-only)
      check_only=true
      ;;
    -h|--help)
      printf '%s\n' 'Usage: build-synology-dev.sh [--check-only]'
      exit 0
      ;;
    *)
      printf 'unknown argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
  shift
done

for command_name in git tar ssh scp; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'required command is not available: %s\n' "$command_name" >&2
    exit 1
  fi
done

if ! command -v rg >/dev/null 2>&1; then
  printf '%s\n' 'required command is not available: rg' >&2
  exit 1
fi

temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-synology-build.XXXXXX")
context_archive="$temp_dir/dotfiles-build-context.tar.gz"
context_listing="$temp_dir/dotfiles-build-context.list"
cleanup() {
  rm -rf "$temp_dir"
}
trap cleanup EXIT

printf '%s\n' 'Preparing a filtered working-tree build context'
(
  cd "$repo_root"
  git ls-files --cached --others --exclude-standard -z \
    | tar \
      --null \
      --files-from=- \
      --exclude-from="$dockerignore" \
      --create \
      --gzip \
      --file="$context_archive"
)

tar --list --gzip --file="$context_archive" >"$context_listing"

# The remote daemon must never receive deployment identities or local state.
# This is an independent safety check in addition to .dockerignore.
forbidden_context_re='(^|/)(\.git|dist|secrets|ssh/\.ssh|\.llm-context|sessions|transcripts|file-history|shell-snapshots)(/|$)|^(llm-context|private-context)/|(^|/)(auth\.json|oauth_creds\.json|credentials\.json|history\.jsonl|state_[^/]*\.sqlite|[^/]*api-?key[^/]*|[^/]*\.env|[^/]*\.pem|[^/]*\.key|id_rsa|id_ed25519)$'
if rg -q "$forbidden_context_re" "$context_listing"; then
  printf '%s\n' 'refusing to send a sensitive path in the Docker build context:' >&2
  rg "$forbidden_context_re" "$context_listing" >&2
  exit 1
fi

for required_context_file in Dockerfile.synology-dev flake.nix flake.lock; do
  if ! rg -q "(^|/)${required_context_file}$" "$context_listing"; then
    printf 'required file is missing from the remote build context: %s\n' "$required_context_file" >&2
    exit 1
  fi
done

printf 'Checking remote Docker access on %s\n' "$remote"
# Expanded by the remote login shell, not this client shell.
# shellcheck disable=SC2016
printf -v remote_preflight \
  'set -eu; test "$(uname -m)" = x86_64; mkdir -p %q/cli-plugins; plugin=%q/cli-plugins/docker-buildx; plugin_tmp="$plugin.tmp"; expected_sha=%q; if [ ! -f "$plugin" ] || [ "$(sha256sum "$plugin" | cut -d " " -f 1)" != "$expected_sha" ]; then curl -fsSL %q -o "$plugin_tmp"; test "$(sha256sum "$plugin_tmp" | cut -d " " -f 1)" = "$expected_sha"; mv "$plugin_tmp" "$plugin"; fi; chmod 755 "$plugin"; sudo -n %q info >/dev/null 2>&1; sudo -n env DOCKER_CONFIG=%q %q buildx version >/dev/null' \
  "$remote_docker_config" \
  "$remote_docker_config" \
  "$buildx_sha256" \
  "$buildx_url" \
  "$remote_docker" \
  "$remote_docker_config" \
  "$remote_docker"
# Commands are assembled with printf %q before crossing the SSH boundary.
# shellcheck disable=SC2029
ssh "$remote" "$remote_preflight"

if "$check_only"; then
  printf 'Remote build preflight passed; filtered context contains %s files (%s bytes compressed).\n' \
    "$(wc -l <"$context_listing" | tr -d '[:space:]')" \
    "$(wc -c <"$context_archive" | tr -d '[:space:]')"
  exit 0
fi

printf 'Building %s for %s directly on %s\n' "$image" "$platform" "$remote"
printf -v remote_build \
  'sudo -n env DOCKER_CONFIG=%q DOCKER_BUILDKIT=1 %q build --platform %q --file %q --tag %q -' \
  "$remote_docker_config" "$remote_docker" "$platform" 'Dockerfile.synology-dev' "$image"
# shellcheck disable=SC2029
ssh "$remote" "$remote_build" <"$context_archive"

env_file="$repo_root/dist/synology-dev/synology-dev.env"
handoff_files=(
  "$compose"
  "$repo_root/scripts/synology-dev-start-services.sh"
  "$repo_root/scripts/synology-dev-start-sshd.sh"
  "$repo_root/scripts/synology-dev-start-tailscale.sh"
  "$repo_root/tests/synology-dev-runtime.sh"
)

if [[ -f "$repo_root/secrets/hosts/synology-dev.yaml" ]]; then
  "$repo_root/scripts/sync-deployment-secrets.sh" synology-dev
  if [[ -f "$env_file" ]]; then
    handoff_files+=("$env_file")
  fi
else
  printf '%s\n' \
    'No secrets/hosts/synology-dev.yaml found; skipping deployment env handoff.' \
    'Run: nix run .#bootstrap-secrets -- env synology-dev tailscale_auth_key' >&2
fi

printf '%s\n' 'Copying Compose definition, startup scripts, runtime test, and optional env file'
# DSM's SSH service may not expose the SFTP subsystem required by modern SCP.
scp -O "${handoff_files[@]}" "$remote:$remote_dir/"

printf -v remote_permissions \
  'chmod 755 %q/*.sh; chmod 644 %q/%q; if [ -f %q/%q ]; then chmod 600 %q/%q; fi' \
  "$remote_dir" \
  "$remote_dir" "$(basename "$compose")" \
  "$remote_dir" "$(basename "$env_file")" \
  "$remote_dir" "$(basename "$env_file")"
# shellcheck disable=SC2029
ssh "$remote" "$remote_permissions"

printf '%s\n' 'Running the container runtime checks on Synology'
printf -v remote_test \
  'sudo -n env PATH=/usr/local/bin:/usr/bin:/bin bash %q/%q %q' \
  "$remote_dir" "$(basename "$repo_root/tests/synology-dev-runtime.sh")" "$image"
# shellcheck disable=SC2029
ssh "$remote" "$remote_test"

printf '\nRemote build complete. The Container Manager project was not started or recreated.\n'
printf 'Image on NAS: %s (%s)\n' "$image" "$platform"
printf 'Project files: %s:%s/\n' "$remote" "$remote_dir"
