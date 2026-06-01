# Dotfiles

Managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Structure

- `bash/`: Bash shell configurations (`.bashrc`, `.profile`, `.bash_logout`)
- `git/`: Git configuration (`.gitconfig`)
- `fish/`: Fish shell configurations
- `fish-linux/`: Linux-specific Fish shell configuration
- `fish-macos/`: macOS-specific Fish shell configuration
- `zellij/`: Zellij terminal multiplexer configuration
- `zed/`, `tabby/`, `cursor/`, `vscode/`, `gh/`, `sublime-text/`: App-specific configuration
- `utilities/`: Various CLI utilities (bat, btop, micro)

## Usage

To install these dotfiles on a new machine:

```bash
git clone https://github.com/esko/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

To only link the dotfiles without installing packages:

```bash
stow --restow -t "$HOME" bash fish fish-linux git ssh zellij zed tabby cursor vscode gh sublime-text utilities
# On macOS, use fish-macos instead of fish-linux.
```
