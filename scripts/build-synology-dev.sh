#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
image='dotfiles-synology-dev:latest'
platform='linux/amd64'
remote='synology'
remote_dir='/volume3/homes/esko/dotfiles-synology-dev'
artifact_dir=${ARTIFACT_DIR:-"$repo_root/dist/synology-dev"}
archive="$artifact_dir/dotfiles-synology-dev-linux-amd64.tar"
checksum="$archive.sha256"
compose="$repo_root/compose/synology-dev.compose.yaml"

for command_name in docker ssh scp; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'required command is not available: %s\n' "$command_name" >&2
    exit 1
  fi
done

if command -v sha256sum >/dev/null 2>&1; then
  checksum_command=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
  checksum_command=(shasum -a 256)
else
  printf '%s\n' 'required checksum command is not available: sha256sum or shasum' >&2
  exit 1
fi

mkdir -p "$artifact_dir"

printf 'Building %s for %s\n' "$image" "$platform"
previous_image_id=$(docker image inspect --format '{{.Id}}' "$image" 2>/dev/null || true)
if ! docker build \
  --platform "$platform" \
  --file "$repo_root/Dockerfile.synology-dev" \
  --tag "$image" \
  "$repo_root"; then
  current_image_id=$(docker image inspect --format '{{.Id}}' "$image" 2>/dev/null || true)
  if [[ -z "$current_image_id" || "$current_image_id" = "$previous_image_id" ]]; then
    printf '%s\n' 'Docker build failed without producing a new image' >&2
    exit 1
  fi
  printf '%s\n' \
    'Docker reported an exporter error, but produced a new image; continuing with runtime verification' >&2
fi

"$repo_root/tests/synology-dev-runtime.sh" "$image"

printf 'Saving uncompressed Docker archive: %s\n' "$archive"
docker save --output "$archive" "$image"

(
  cd "$artifact_dir"
  "${checksum_command[@]}" "$(basename "$archive")" >"$(basename "$checksum")"
)

printf 'Creating remote handoff directory: %s:%s\n' "$remote" "$remote_dir"
ssh "$remote" mkdir -p "$remote_dir"

env_file="$artifact_dir/synology-dev.env"
handoff_files=(
  "$archive"
  "$checksum"
  "$compose"
  "$repo_root/scripts/synology-dev-start-services.sh"
  "$repo_root/scripts/synology-dev-start-sshd.sh"
  "$repo_root/scripts/synology-dev-start-tailscale.sh"
)

if [[ -f "$repo_root/secrets/hosts/synology-dev.yaml" ]]; then
  "$repo_root/scripts/sync-deployment-secrets.sh" synology-dev
  if [[ -f "$env_file" ]]; then
    handoff_files+=("$env_file")
  fi
else
  printf '%s\n' \
    'No secrets/hosts/synology-dev.yaml found; skipping deployment env handoff.' \
    'Run: ./update.sh --bootstrap-secrets after adding env secrets.' >&2
fi

printf '%s\n' 'Copying image archive, checksum, Compose definition, startup scripts, and env file'
# DSM's SSH service may not expose the SFTP subsystem required by modern SCP.
# Force the legacy SCP transport, which is supported by the target NAS.
scp -O "${handoff_files[@]}" "$remote:$remote_dir/"

if [[ -f "$env_file" ]]; then
  printf '%s\n' 'Restricting the remote Tailscale env file to owner-read only'
  ssh "$remote" chmod 600 "$remote_dir/$(basename "$env_file")"
fi

printf '%s\n' 'Verifying the transferred archive checksum on Synology'
printf -v remote_verify \
  'cd %q && sha256sum -c %q' \
  "$remote_dir" "$(basename "$checksum")"
# The command is intentionally assembled and shell-escaped on the client; ssh
# passes it to the Synology login shell as one remote command.
# shellcheck disable=SC2029
ssh "$remote" "$remote_verify"

printf '\nHandoff complete. The image has not been loaded or started.\n'
printf 'Remote artifacts: %s:%s/\n' "$remote" "$remote_dir"
