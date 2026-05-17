# SYSTEM CONTEXT: DOTFILES & ENVIRONMENT ARCHITECTURE

## 1. Core Architecture
* **Dotfiles Manager:** GNU Stow (mirroring the home directory structure).
* **Primary Shell:** Fish Shell.
* **Multi-OS Strategy:** Configurations are split into Stow packages: `fish` (common), `fish-linux` (Linux specific), and `fish-macos` (Mac specific).
* **Loading Mechanism:** Relies entirely on Fish's native `~/.config/fish/conf.d/` auto-loading. OS-specific packages drop numbered `.fish` files into this directory to override or append environment logic without messy `if/else` OS checks.

## 2. Directory Structure (`~/dotfiles/`)
* `fish/`: The universal package stowed on all machines.
* `fish-linux/`: Stowed only on Linux (`conf.d/99-linux.fish` for apt/systemd abbreviations).
* `fish-macos/`: Stowed only on Mac (`conf.d/99-macos.fish` for Homebrew paths/abbreviations).
* `git/`: Global `.gitconfig` (configured to use `hunk` pager).
* `posh/`: Oh My Posh theme (`.mytheme.omp.json`).
* `ssh/`: `.ssh/config` for aliases, strictly ignoring keys (`id_*`) via `.gitignore`.
* `zellij/`: Multiplexer config (`.config/zellij/config.kdl`).

## 3. Tool Stack
* **Core replacements:** `eza` (ls), `bat` (cat), `fd` (find), `rg` (grep), `micro` (vim).
* **Workflow enhancements:** `fzf` (fuzzy finding), `zoxide` (cd), `lazygit` (git UI).
* **Prompt/Multiplexer:** Zellij (session persistence & OSC52 clipboard for SSH).

## 4. Custom Functions
* `rfv`: Combines `rg` + `fzf` + `bat` + `micro` to search project files, preview with syntax highlighting, and open the editor to the exact matched line.
* `mkcd`: Creates a directory and enters it immediately.
* `backup`: Creates a timestamped `.bak` copy of a target file.
* `extract`: A universal archive extractor with a switch statement for tar, zip, gz, rar, 7z.

**Rule for future responses:** When suggesting changes to my shell configuration, always adapt them to fit this GNU Stow `conf.d/` structure or use Fish native `abbr` and lazy-loaded `functions/` instead of legacy Bash aliases.
