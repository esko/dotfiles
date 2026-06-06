# Dotfiles

Managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Structure

- `bash/`: Bash shell configurations (`.bashrc`, `.profile`, `.bash_logout`)
- `git/`: Git configuration (`.gitconfig`)
- `fish/`: Fish shell configurations
- `fish-linux/`: Linux-specific Fish shell configuration
- `fish-macos/`: macOS-specific Fish shell configuration
- `zellij/`: Zellij terminal multiplexer configuration
- `zed/`, `cursor/`, `vscode/`, `gh/`, `sublime-text/`: Stowed app configuration
- `templates/tabby/`: Seed configuration that preserves Tabby's machine-local vault
- `utilities/`: Various CLI utilities (bat, btop, micro)

## Usage

To install these dotfiles on a new machine:

```bash
git clone https://github.com/esko/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

The installer also sets up rustup, Node.js via fnm, uv, Claude Code, ShellCheck,
and the platform-specific development packages declared in `install.sh` and
`Brewfile`.

To only link the dotfiles without installing packages:

```bash
stow --restow -t "$HOME" bash fish fish-linux git ssh zellij zed cursor vscode gh sublime-text utilities
# On macOS, use fish-macos instead of fish-linux.
```
