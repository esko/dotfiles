# Legacy setup audit

The repository now has one supported entrypoint: the Nix flake and its
Home Manager/nix-darwin outputs. Former GNU Stow installer and package trees
were removed after checking that no active module or test referenced them:

- `install.sh`, `Brewfile`, and the old `GEMINI.md` architecture note
- Bash and Fish package trees (`bash/`, `fish/`, `fish-linux/`, and
  `fish-macos/`)
- the unused Tabby seed (`templates/tabby/config.yaml`)
- Stow-only ignore files and the obsolete Zellij backup (`config.kdl.bak.1`)
- orphan Stow packages `git/`, `gh/`, `cursor/`, `vscode/`, `zed/`, and
  `sublime-text/` (settings live under `config/editors/` and
  `modules/shared/editors.nix`; `gh` is `programs.gh`)

## Retained / hand-maintained

- `ssh/.ssh/config` remains a hand-maintained SSH configuration. Home
  Manager writes only generated include fragments under `~/.ssh/config.d/`.
- `ssh/.ssh/id_rsa.age` and `scripts/encrypt-ssh-key.sh` are legacy encrypted
  RSA-key migration material. They are not read by the flake, are not
  decrypted during activation, and must not be used for new hosts. New keys
  use per-host Ed25519 SOPS secrets under `ssh/<host>/id_ed25519`.
- `ssh/.ssh/known_hosts*` are machine-local and gitignored.

## Migration hooks that stay on purpose

- Legacy GNU Stow directory symlinks under `~/.config` are removed
  automatically during Home Manager activation. See
  `modules/shared/stow-migration.nix`.
- Managed `home.file` entries keep `force = true` so activation stays
  idempotent while hosts may still have pre-HM file collisions. Narrow force
  only after every host activates without creating new
  `*.home-manager-backup` files.

## GitHub protocol policy

`programs.git` and `programs.gh` both default to HTTPS with
`gh auth git-credential`. Hosts that enroll an SSH key may use SSH remotes
without a global `url.insteadOf` rewrite. If `gh/.config/gh/hosts.yml` was
ever committed historically, rotate that GitHub token.

Do not add new package installation logic outside the flake. Add host-specific
packages to the appropriate Nix module or document a manual host bootstrap
step when the package is outside Home Manager's scope.
