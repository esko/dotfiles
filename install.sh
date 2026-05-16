#!/bin/bash

set -e

echo "========================================"
echo "  Dotfiles Automated Installation       "
echo "========================================"

# 1. OS Detection & Package Installation
OS="$(uname -s)"
if [ "$OS" = "Linux" ]; then
    echo "=> Linux detected. Installing core dependencies via apt..."
    sudo apt-get update
    sudo apt-get install -y stow fish age curl git wget
    
    STOW_OS="fish-linux"
elif [ "$OS" = "Darwin" ]; then
    echo "=> macOS detected."
    if ! command -v brew >/dev/null 2>&1; then
        echo "=> Homebrew not found. Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    echo "=> Running Homebrew bundle..."
    brew bundle --file="$HOME/dotfiles/Brewfile"
    
    STOW_OS="fish-macos"
else
    echo "=> Unsupported OS: $OS"
    exit 1
fi

# 2. Decrypt SSH Keys
echo "=> Checking SSH keys..."
if [ ! -f "$HOME/.ssh/id_rsa" ]; then
    if [ -f "$HOME/dotfiles/ssh/.ssh/id_rsa.age" ]; then
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        echo "=> Encrypted SSH key found. Please enter your passphrase to decrypt:"
        age -d -o "$HOME/.ssh/id_rsa" "$HOME/dotfiles/ssh/.ssh/id_rsa.age"
        chmod 600 "$HOME/.ssh/id_rsa"
        echo "=> SSH key successfully decrypted."
    else
        echo "=> No encrypted SSH key found at ~/dotfiles/ssh/.ssh/id_rsa.age. Skipping."
    fi
else
    echo "=> SSH key already exists at ~/.ssh/id_rsa. Skipping decryption."
fi

# 3. Stow Packages
echo "=> Stowing configuration packages..."
cd "$HOME/dotfiles"
stow --restow -t ~ fish
stow --restow -t ~ "$STOW_OS"
stow --restow -t ~ ssh

# Safely stow git and zellij if directories exist
if [ -d "git" ]; then stow --restow -t ~ git; fi
if [ -d "zellij" ]; then stow --restow -t ~ zellij; fi

# 4. Set Default Shell
echo "=> Setting Fish as the default shell..."
FISH_PATH="$(which fish)"
if ! grep -q "$FISH_PATH" /etc/shells; then
    echo "$FISH_PATH" | sudo tee -a /etc/shells
fi

if [ "$OS" = "Darwin" ]; then
    CURRENT_SHELL="$(dscl . -read /Users/$USER UserShell | awk '{print $2}')"
else
    CURRENT_SHELL="$(getent passwd $USER | awk -F: '{print $7}')"
fi

if [ "$CURRENT_SHELL" != "$FISH_PATH" ]; then
    echo "=> Changing shell to $FISH_PATH. You may be prompted for your password."
    sudo chsh -s "$FISH_PATH" "$USER"
else
    echo "=> Fish is already the default shell."
fi

echo "========================================"
echo "  Installation Complete!                "
echo "  Please restart your terminal session. "
echo "========================================"
