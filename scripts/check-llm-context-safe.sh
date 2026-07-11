#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    printf 'Run this check inside the dotfiles Git repository.\n' >&2
    exit 2
}
cd "$repo_root"

status=0
while IFS= read -r -d '' path; do
    case "$path" in
        */auth.json|*/oauth_creds.json|*/credentials.json|*/history.jsonl|*/sessions/*|*/transcripts/*|*/file-history/*|*/shell-snapshots/*|*/state_*.sqlite|*api-key*|*apikey*|*.env|*.pem|*.key|*/id_rsa|*/id_ed25519)
            printf 'sensitive tracked path: %s\n' "$path" >&2
            status=1
            ;;
    esac
done < <(git ls-files -z)

# Detect common token formats without flagging documentation that mentions
# filenames. Encrypted age files are intentionally allowed by this check.
token_pattern='(^|[^A-Za-z])(sk-[A-Za-z0-9]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|AIza[A-Za-z0-9_-]{30,}|xox[baprs]-[A-Za-z0-9-]{20,}|AKIA[A-Z0-9]{16}|-----BEGIN (OPENSSH|RSA|EC|DSA) PRIVATE KEY-----)'
if git grep -n -I -E "$token_pattern" -- ':!scripts/check-llm-context-safe.sh' >/dev/null; then
    printf 'possible API/OAuth token found in tracked content\n' >&2
    git grep -n -I -E "$token_pattern" -- ':!scripts/check-llm-context-safe.sh' >&2 || true
    status=1
fi

if [ "$status" -eq 0 ]; then
    printf 'LLM context safety check passed.\n'
fi
exit "$status"
