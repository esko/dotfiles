#!/bin/bash

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_brew() {
    if command -v brew >/dev/null 2>&1; then
        command -v brew
    elif [ -x /opt/homebrew/bin/brew ]; then
        echo /opt/homebrew/bin/brew
    elif [ -x /usr/local/bin/brew ]; then
        echo /usr/local/bin/brew
    else
        return 1
    fi
}

activate_homebrew() {
    local brew_bin
    brew_bin="$(find_brew)" || return 1
    eval "$("$brew_bin" shellenv)"
}

persist_homebrew_path() {
    local brew_bin shell_name startup_file init_line

    brew_bin="$(find_brew)" || return 1
    shell_name="$(basename "${SHELL:-}")"

    case "$shell_name" in
        fish|bash)
            # These are configured by the dotfiles stowed later in this script.
            return 0
            ;;
        zsh)
            startup_file="$HOME/.zprofile"
            ;;
        *)
            startup_file="$HOME/.profile"
            ;;
    esac

    init_line="eval \"\$($brew_bin shellenv)\""
    touch "$startup_file"

    if ! grep -Fqx "$init_line" "$startup_file"; then
        printf '\n%s\n' "$init_line" >> "$startup_file"
    fi
}

echo "========================================"
echo "  Dotfiles Automated Installation       "
echo "========================================"

# 1. OS Detection & Package Installation
OS="$(uname -s)"
if [ "$OS" = "Linux" ]; then
    echo "=> Linux detected. Setting up repositories and installing packages..."

    # Tools used while adding third-party repositories on a fresh system.
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg wget
    
    # Create keyrings directory
    sudo mkdir -p -m 755 /etc/apt/keyrings
    
    # 1. Fish 4.x
    if [ ! -f /etc/apt/sources.list.d/shells:fish:release:4.list ]; then
        echo "=> Adding Fish 4.x repository..."
        curl -fsSL https://download.opensuse.org/repositories/shells:fish:release:4/Debian_12/Release.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/shells_fish_release_4.gpg > /dev/null
        echo "deb http://download.opensuse.org/repositories/shells:/fish:/release:/4/Debian_12/ /" | sudo tee /etc/apt/sources.list.d/shells:fish:release:4.list > /dev/null
    fi

    # 2. GitHub CLI
    if [ ! -f /etc/apt/sources.list.d/github-cli.list ]; then
        echo "=> Adding GitHub CLI repository..."
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    fi
    
    # 3. Zed Editor (Julian Fairfax repository)
    if [ ! -f /etc/apt/sources.list.d/julians-package-repo.list ]; then
        echo "=> Adding Zed repository..."
        curl -fsSL https://julianfairfax.codeberg.page/package-repo/pubkey.gpg | gpg --dearmor | sudo tee /usr/share/keyrings/julians-package-repo.gpg > /dev/null
        echo "deb [ signed-by=/usr/share/keyrings/julians-package-repo.gpg ] https://julianfairfax.codeberg.page/package-repo/debs packages main" | sudo tee /etc/apt/sources.list.d/julians-package-repo.list > /dev/null
    fi

    # 4. Tabby Terminal
    if [ ! -f /etc/apt/sources.list.d/eugeny_tabby.list ]; then
        echo "=> Adding Tabby Terminal repository..."
        curl -fsSL https://packagecloud.io/eugeny/tabby/gpgkey | gpg --dearmor | sudo tee /etc/apt/keyrings/eugeny_tabby-archive-keyring.gpg > /dev/null
        echo "deb [signed-by=/etc/apt/keyrings/eugeny_tabby-archive-keyring.gpg] https://packagecloud.io/eugeny/tabby/debian/ bookworm main" | sudo tee /etc/apt/sources.list.d/eugeny_tabby.list > /dev/null
    fi

    # 5. Sublime Text
    if [ ! -f /etc/apt/sources.list.d/sublime-text.sources ]; then
        echo "=> Adding Sublime Text repository..."
        curl -fsSL https://download.sublimetext.com/sublimehq-pub.gpg | gpg --dearmor | sudo tee /etc/apt/keyrings/sublimehq-pub.asc > /dev/null
        echo "Types: deb
URIs: https://download.sublimetext.com/
Suites: apt/stable/
Signed-By: /etc/apt/keyrings/sublimehq-pub.asc" | sudo tee /etc/apt/sources.list.d/sublime-text.sources > /dev/null
    fi

    # 6. Cursor Editor
    if [ ! -f /etc/apt/sources.list.d/cursor.sources ]; then
        echo "=> Adding Cursor repository..."
        curl -fsSL https://downloads.cursor.com/aptrepo/pubkey.gpg | gpg --dearmor | sudo tee /usr/share/keyrings/anysphere.gpg > /dev/null
        echo "Types: deb
URIs: https://downloads.cursor.com/aptrepo
Suites: stable
Components: main
Architectures: amd64,arm64
Signed-By: /usr/share/keyrings/anysphere.gpg" | sudo tee /etc/apt/sources.list.d/cursor.sources > /dev/null
    fi

    # 7. VS Code
    if [ ! -f /etc/apt/sources.list.d/vscode.list ]; then
        echo "=> Adding VS Code repository..."
        curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/keyrings/packages.microsoft.gpg > /dev/null
        echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
    fi

    # Update and Install
    echo "=> Updating package lists and installing software..."
    sudo apt-get update
    sudo apt-get install -y stow fish age curl git wget build-essential \
        vulkan-tools lsb-release nano adw-gtk3 \
        python3-secretstorage python3-gi gir1.2-secret-1 gnome-keyring libsecret-tools python3-pip \
        python3-venv pipx pciutils shellcheck \
        gh zed tabby-terminal sublime-text cursor code vlc

    STOW_OS="fish-linux"
elif [ "$OS" = "Darwin" ]; then
    echo "=> macOS detected."
    if ! find_brew >/dev/null 2>&1; then
        echo "=> Homebrew not found. Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    if ! activate_homebrew; then
        echo "=> Homebrew installation failed or brew could not be located."
        exit 1
    fi

    if ! persist_homebrew_path; then
        echo "=> Failed to configure Homebrew for the detected shell."
        exit 1
    fi

    echo "=> Running Homebrew bundle..."
    brew bundle --file="$DOTFILES_DIR/Brewfile"
    
    STOW_OS="fish-macos"
else
    echo "=> Unsupported OS: $OS"
    exit 1
fi

# 2. Rust and Cargo via rustup
if [ ! -x "$HOME/.cargo/bin/rustup" ]; then
    echo "=> Installing Rust and Cargo via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
fi
export PATH="$HOME/.cargo/bin:$PATH"

# 3. Developer CLIs
if [ "$OS" = "Linux" ] && ! command -v uv >/dev/null 2>&1; then
    echo "=> Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh
fi

if ! command -v claude >/dev/null 2>&1; then
    echo "=> Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash
fi

# 4. Node.js via fnm
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
    fnm use lts/latest
else
    echo "=> fnm installation failed or not found."
fi

# 5. Cargo Packages (Linux only)
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

# 6. NPM Packages
echo "=> Installing global NPM packages..."
if command -v npm >/dev/null 2>&1; then
    npm install -g hunkdiff @google/gemini-cli @openai/codex @google/jules agent-browser command-code pnpm
else
    echo "=> npm not found. Skipping NPM packages."
fi

# 7. Decrypt SSH Keys
echo "=> Checking SSH keys..."
if [ ! -f "$HOME/.ssh/id_rsa" ]; then
    if [ -f "$DOTFILES_DIR/ssh/.ssh/id_rsa.age" ]; then
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        echo "=> Encrypted SSH key found. Please enter your passphrase to decrypt:"
        age -d -o "$HOME/.ssh/id_rsa" "$DOTFILES_DIR/ssh/.ssh/id_rsa.age"
        chmod 600 "$HOME/.ssh/id_rsa"
        echo "=> SSH key successfully decrypted."
    else
        echo "=> No encrypted SSH key found at $DOTFILES_DIR/ssh/.ssh/id_rsa.age. Skipping."
    fi
else
    echo "=> SSH key already exists at ~/.ssh/id_rsa. Skipping decryption."
fi

# 8. Stow Packages
echo "=> Stowing configuration packages..."
cd "$DOTFILES_DIR"

# Prevent Stow from folding directories that also contain machine-local state.
mkdir -p \
    "$HOME/.config/fish" \
    "$HOME/.config/gh" \
    "$HOME/.config/btop" \
    "$HOME/.config/micro"

stow_package() {
    local pkg="$1"
    if [ -d "$pkg" ]; then
        stow --restow -t "$HOME" "$pkg"
    else
        echo "=> Stow package '$pkg' not found. Skipping."
    fi
}

for pkg in bash fish "$STOW_OS" ssh git zellij zed cursor vscode gh sublime-text utilities; do
    stow_package "$pkg"
done

# Seed Tabby without replacing machine-local vault data.
TABBY_CONFIG="$HOME/.config/tabby/config.yaml"
if [ ! -e "$TABBY_CONFIG" ]; then
    echo "=> Seeding Tabby configuration..."
    mkdir -p "$(dirname "$TABBY_CONFIG")"
    cp "$DOTFILES_DIR/templates/tabby/config.yaml" "$TABBY_CONFIG"
    chmod 600 "$TABBY_CONFIG"
fi

# 9. Set Default Shell
echo "=> Setting Fish as the default shell..."
FISH_PATH="$(which fish)"
if ! grep -q "$FISH_PATH" /etc/shells; then
    echo "$FISH_PATH" | sudo tee -a /etc/shells
fi

if [ "$OS" = "Darwin" ]; then
    CURRENT_SHELL="$(dscl . -read /Users/"$USER" UserShell | awk '{print $2}')"
else
    CURRENT_SHELL="$(getent passwd "$USER" | awk -F: '{print $7}')"
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
