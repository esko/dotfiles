# Legacy setup audit

The repository now has one supported entrypoint: the Nix flake and its
Home Manager/nix-darwin outputs. The former GNU Stow installer and package
trees were removed after checking that no active module or test referenced
them:

- `install.sh`, `Brewfile`, and the old `GEMINI.md` architecture note
- Bash and Fish package trees (`bash/`, `fish/`, `fish-linux/`, and
  `fish-macos/`)
- the unused Tabby seed (`templates/tabby/config.yaml`)
- Stow-only ignore files and the obsolete Zellij backup

The following files are intentionally retained:

- `ssh/.ssh/config` remains a hand-maintained SSH configuration. Home
  Manager writes only the generated include fragment under
  `~/.ssh/config.d/`.
- `ssh/.ssh/id_rsa.age` and `scripts/encrypt-ssh-key.sh` are legacy encrypted
  RSA-key migration material. They are not read by the flake, are not
  decrypted during activation, and must not be used for new hosts. New keys
  use per-host Ed25519 SOPS secrets under `ssh/<host>/id_ed25519`.
- The editor and utility configuration directories remain where they are
  consumed by Home Manager or still represent user-owned settings awaiting a
  dedicated module.
- Legacy GNU Stow directory symlinks under `~/.config` (for example
  `~/.config/bat` pointing into this repository) are removed automatically
  during Home Manager activation. See `modules/shared/stow-migration.nix`.
  Editor trees such as `~/.config/Code` may still use manual stow links until
  they gain a Home Manager module.

Do not add new package installation logic to the removed installer. Add
  host-specific packages to the appropriate Nix module or document a manual
  host bootstrap step when the package is outside Home Manager's scope.
