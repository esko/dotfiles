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
# PEM private-key markers are handled separately below because a bare
# "-----BEGIN ... PRIVATE KEY-----" line followed by "..." (as in
# secrets/README.md's schema snippet) is documentation, not a leak.
token_pattern='(^|[^A-Za-z])(sk-[A-Za-z0-9]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|AIza[A-Za-z0-9_-]{30,}|xox[baprs]-[A-Za-z0-9-]{20,}|AKIA[A-Z0-9]{16})'
if git grep -n -I -E "$token_pattern" -- ':!scripts/check-llm-context-safe.sh' >/dev/null; then
    printf 'possible API/OAuth token found in tracked content\n' >&2
    git grep -n -I -E "$token_pattern" -- ':!scripts/check-llm-context-safe.sh' >&2 || true
    status=1
fi

# Detect real PEM private-key blocks. A BEGIN marker on its own (or followed by
# a "..." placeholder, as in secrets/README.md) is documentation. Require the
# next non-blank line to look like actual PEM base64 (20+ chars from the base64
# alphabet, optionally padded) or a legacy encrypted-PEM header before flagging.
# This keeps detection of real key blocks intact without excluding the README.
pem_marker='-----BEGIN (OPENSSH|RSA|EC|DSA) PRIVATE KEY-----'
while IFS= read -r match; do
    [[ -n "$match" ]] || continue
    file=${match%%:*}
    rest=${match#*:}
    line=${rest%%:*}
    next=$(awk -v start="$((line+1))" '
        NR>=start && $0 ~ /[[:graph:]]/ {
            sub(/\r$/, "")
            print
            exit
        }' "$file" 2>/dev/null || true)
    if [[ "$next" =~ ^[[:space:]]*[A-Za-z0-9+/]{20,}={0,2}[[:space:]]*$ ]] \
        || [[ "$next" =~ ^[[:space:]]*(Proc-Type|DEK-Info): ]]; then
        printf 'private key block in %s:%s\n' "$file" "$line" >&2
        status=1
    fi
done < <(git grep -n -I -E -e "$pem_marker" -- ':!scripts/check-llm-context-safe.sh' || true)

if [ "$status" -eq 0 ]; then
    printf 'LLM context safety check passed.\n'
fi
exit "$status"
