# shellcheck shell=bash
set -euo pipefail

umask 022
for state_dir in \
  "$HOME/.cache" \
  "$HOME/.config" \
  "$HOME/.grok" \
  "$HOME/.local" \
  "$HOME/.local/share" \
  "$HOME/.local/state"; do
  mkdir -p "$state_dir"
  chmod u+rwx "$state_dir"
done

# ~/.grok is a named volume, so it can outlive the image that first populated
# it. Refresh the declarative, non-secret config on every container start while
# leaving credentials and other Grok state in the volume/environment.
if [[ -f /etc/dotfiles/grok/config.toml ]]; then
  install -Dm644 /etc/dotfiles/grok/config.toml "$HOME/.grok/config.toml"
fi

if [[ $# -eq 0 ]]; then
  set -- zsh -l
fi

exec "$@"
