{ config, lib, ... }:

let
  # Idempotent migration for hosts that still have whole-directory Stow
  # symlinks under ~/.config. Safe to keep: it only removes a symlink and
  # recreates a real directory when needed. Shrink this list only after every
  # host has activated at least once without those symlinks present.
  #
  # GNU Stow used to symlink whole app directories from ~/.config into the
  # dotfiles tree. Home Manager now manages individual files under those paths.
  # When the parent directory is still a stow symlink, link activation follows
  # it and overwrites repository sources instead of creating store links.
  legacyStowDirs = [
    ".config/bat"
    ".config/btop"
    ".config/micro"
    ".config/zellij"
    # Former Stow editor/gh packages used whole-directory symlinks on Linux.
    ".config/Cursor"
    ".config/Code"
    ".config/zed"
    ".config/sublime-text"
    ".config/gh"
  ];
in
{
  home.activation.removeLegacyStowSymlinks = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
    ${config.lib.bash.initHomeManagerLib}

    ${lib.concatMapStrings (rel: ''
      if [[ -L "$HOME/${rel}" ]]; then
        verboseEcho "Removing legacy stow symlink $HOME/${rel} -> $(readlink "$HOME/${rel}")"
        run rm $VERBOSE_ARG "$HOME/${rel}"
        run mkdir -p $VERBOSE_ARG "$HOME/${rel}"
      fi
    '') legacyStowDirs}
  '';
}
