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
    sudo apt-get install -y stow fish age curl git wget build-essential
    
    # Check Fish version and upgrade if < 4.0
    FISH_VERSION=$(fish --version | awk '{print $3}')
    REQUIRED_VERSION="4.0.0"
    if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$FISH_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]; then
        echo "=> Fish version $FISH_VERSION is older than $REQUIRED_VERSION. Upgrading..."
        # Debian OBS repository for Fish 4.x
        echo "=> Adding Fish 4.x repository for Debian..."
        curl -fsSL https://download.opensuse.org/repositories/shells:fish:release:4/Debian_12/Release.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/shells_fish_release_4.gpg > /dev/null
        echo "deb http://download.opensuse.org/repositories/shells:/fish:/release:/4/Debian_12/ /" | sudo tee /etc/apt/sources.list.d/shells:fish:release:4.list > /dev/null
        
        sudo apt-get update
        sudo apt-get install -y fish
    fi

    # Install Rust if not present
    if ! command -v cargo >/dev/null 2>&1; then
        echo "=> Installing Rust via rustup..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
        export PATH="$HOME/.cargo/bin:$PATH"
    fi

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

# 2. Node.js via fnm
echo "=> Setting up fnm and Node.js..."
if ! command -v fnm >/dev/null 2>&1; then
    if [ "$OS" = "Linux" ] && command -v cargo >/dev/null 2>&1; then
        echo "=> Installing fnm via cargo..."
        cargo install fnm
        export PATH="$HOME/.cargo/bin:$PATH"
    else
        echo "=> Installing fnm..."
        curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir "$HOME/.local/share/fnm" --skip-shell
        export PATH="$HOME/.local/share/fnm:$PATH"
    fi
fi

if command -v fnm >/dev/null 2>&1; then
    eval "$(fnm env --shell bash)"
    echo "=> Installing Node.js (LTS) via fnm..."
    fnm install --lts
    fnm use lts
else
    echo "=> fnm installation failed or not found."
fi

# 3. Cargo Packages (Linux only)
if [ "$OS" = "Linux" ] && command -v cargo >/dev/null 2>&1; then
    echo "=> Installing Cargo packages..."
    for pkg in bat eza zellij; do
        if ! command -v $pkg >/dev/null 2>&1; then
            cargo install $pkg
        else
            echo "=> $pkg is already installed. Skipping."
        fi
    done
fi

# 4. NPM Packages
echo "=> Installing global NPM packages..."
if command -v npm >/dev/null 2>&1; then
    npm install -g hunkdiff @google/gemini-cli @openai/codex
else
    echo "=> npm not found. Skipping NPM packages."
fi

# 5. Decrypt SSH Keys
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

# 6. Stow Packages
echo "=> Stowing configuration packages..."
cd "$HOME/dotfiles"
stow --restow -t ~ fish
stow --restow -t ~ "$STOW_OS"
stow --restow -t ~ ssh

# Safely stow git and zellij if directories exist
if [ -d "git" ]; then stow --restow -t ~ git; fi
if [ -d "zellij" ]; then stow --restow -t ~ zellij; fi

# 7. Set Default Shell
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
