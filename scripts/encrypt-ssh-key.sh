#!/bin/bash

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_KEY="$HOME/.ssh/id_rsa"
ENCRYPTED_KEY="$DOTFILES_DIR/ssh/.ssh/id_rsa.age"

if [ ! -f "$SOURCE_KEY" ]; then
    echo "SSH private key not found at $SOURCE_KEY."
    exit 1
fi

age -p -o "$ENCRYPTED_KEY" "$SOURCE_KEY"
chmod 600 "$ENCRYPTED_KEY"
echo "Encrypted SSH key written to $ENCRYPTED_KEY."
