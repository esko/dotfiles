#!/usr/bin/env bash
# Install the Lefthook git hooks manager binary.
set -euo pipefail

LEFTHOOK_VERSION="${LEFTHOOK_VERSION:-2.1.9}"
INSTALL_DIR="${LEFTHOOK_INSTALL_DIR:-$HOME/.local/bin}"

install_lefthook() {
    if command -v lefthook >/dev/null 2>&1; then
        echo "=> lefthook is already installed ($(command -v lefthook)). Skipping."
        return 0
    fi

    local os machine asset url

    case "$(uname -s)" in
        Darwin)
            if command -v brew >/dev/null 2>&1; then
                echo "=> Installing lefthook via Homebrew..."
                brew install lefthook
                return 0
            fi
            os="MacOS"
            ;;
        Linux)
            os="Linux"
            ;;
        *)
            echo "=> Unsupported OS for lefthook install: $(uname -s)" >&2
            return 1
            ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64) machine="x86_64" ;;
        aarch64|arm64) machine="arm64" ;;
        *)
            echo "=> Unsupported architecture for lefthook: $(uname -m)" >&2
            return 1
            ;;
    esac

    asset="lefthook_${LEFTHOOK_VERSION}_${os}_${machine}"
    url="https://github.com/evilmartians/lefthook/releases/download/v${LEFTHOOK_VERSION}/${asset}"

    mkdir -p "$INSTALL_DIR"
    echo "=> Installing lefthook ${LEFTHOOK_VERSION} to ${INSTALL_DIR}/lefthook..."
    curl -fsSL "$url" -o "${INSTALL_DIR}/lefthook"
    chmod +x "${INSTALL_DIR}/lefthook"
    echo "=> lefthook installed: $("${INSTALL_DIR}/lefthook" version)"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_lefthook
fi
