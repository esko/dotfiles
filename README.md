# Dotfiles

Managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Structure

- `bash/`: Bash shell configurations (`.bashrc`, `.profile`, `.bash_logout`)
- `git/`: Git configuration (`.gitconfig`)
- `fish/`: Fish shell configurations
- `ghostty/`: Ghostty terminal configuration
- `zellij/`: Zellij terminal multiplexer configuration
- `utilities/`: Various CLI utilities (bat, btop, micro)

## Usage

To install these dotfiles on a new machine:

```bash
git clone https://github.com/esko/dotfiles.git ~/dotfiles
cd ~/dotfiles
stow bash git fish ghostty zellij utilities
```
