#!/usr/bin/env bash
# Nix manifest helpers shared by secret sync, render, and consumer scripts.
#
# Flake installable attr paths (.#foo.bar) do not accept Nix `or` operators in
# the path. Optional fields are read via JSON + jq instead.

manifest_eval_raw() {
  nix eval --raw "$1" 2>/dev/null
}

manifest_eval_json() {
  nix eval --json "$1" 2>/dev/null
}

manifest_env_key_declared() {
  local env_key=$1
  manifest_eval_json ".#secretsManifest.envKeys" \
    | jq -e --arg key "$env_key" 'has($key)' >/dev/null 2>&1
}

manifest_shared_env_keys_json() {
  manifest_eval_json ".#secretsManifest.shared.env" || printf '[]'
}

manifest_env_key_shared() {
  local env_key=$1
  manifest_eval_json ".#secretsManifest.shared.env" \
    | jq -e --arg key "$env_key" 'index($key)' >/dev/null 2>&1
}

manifest_deployment_env_keys_json() {
  local deployment=$1
  manifest_eval_json ".#secretsManifest.deployments.${deployment}.env" || printf '[]'
}

manifest_deployment_wants_ssh() {
  local deployment=$1
  manifest_eval_json ".#secretsManifest.deployments.${deployment}.ssh" 2>/dev/null || printf 'false'
}

manifest_deployment_consumers_json() {
  local deployment=$1
  manifest_eval_json ".#secretsManifest" \
    | jq -c --arg dep "$deployment" '
        (.deployments[$dep].env // []) as $env
        | [.consumers // {} | to_entries[]
            | select(.value.envKey as $key | $env | index($key))
            | select((.value.skipDeployments // []) | index($dep) | not)
            | .key]
      '
}

manifest_consumer_script() {
  local consumer=$1
  manifest_eval_raw ".#secretsManifest.consumers.${consumer}.script"
}

manifest_consumer_env_key() {
  local consumer=$1
  manifest_eval_raw ".#secretsManifest.consumers.${consumer}.envKey"
}

manifest_consumer_hostname_attr() {
  local consumer=$1
  manifest_eval_json ".#secretsManifest.consumers.${consumer}" \
    | jq -r '.hostnameAttr // empty'
}

manifest_deployment_attr() {
  local deployment=$1 attr=$2 fallback=${3:-}
  local value
  value=$(
    manifest_eval_json ".#secretsManifest.deployments.${deployment}" \
      | jq -r --arg attr "$attr" '.[$attr] // empty'
  ) || true
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$fallback"
  fi
}

manifest_consumer_hostname() {
  local deployment=$1 consumer=$2
  local hostname_attr hostname

  hostname_attr=$(manifest_consumer_hostname_attr "$consumer")
  if [[ -n "$hostname_attr" ]]; then
    hostname=$(manifest_deployment_attr "$deployment" "$hostname_attr" "$deployment")
    printf '%s\n' "$hostname"
    return 0
  fi

  printf '%s\n' "$deployment"
}
