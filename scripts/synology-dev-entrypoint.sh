# shellcheck shell=bash
set -euo pipefail

umask 022
for state_dir in \
  "$HOME/.cache" \
  "$HOME/.config" \
  "$HOME/.local" \
  "$HOME/.local/share" \
  "$HOME/.local/state"; do
  mkdir -p "$state_dir"
  chmod u+rwx "$state_dir"
done

if [[ $# -eq 0 ]]; then
  set -- zsh -l
fi

exec "$@"
