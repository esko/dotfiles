{ config, lib, pkgs, ... }:

let
  # Idempotent migration for hosts that still have whole-directory Stow
  # symlinks under ~/.config. Safe to keep: it only removes a symlink and
  # recreates a real directory when the symlink actually points back into
  # this dotfiles checkout or follows the legacy Stow layout. Shrink this
  # list only after every host has activated at least once without those
  # symlinks present.
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
  options.dotfiles.stowMigration.forceLegacyCollisions = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Replace unmanaged files at former Stow paths during Home Manager
      activation. Disable per host after its legacy directory migration has
      completed and the managed paths are known to be collision-free.
    '';
  };

  config.home.activation.removeLegacyStowSymlinks = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
    ${config.lib.bash.initHomeManagerLib}

    # macOS readlink has no -f. Resolve a symlink portably by resolving its
    # parent directory with the shell, then reattaching the basename.
    resolveLinkTarget() {
      local linkPath="$1"
      local rawTarget targetPath resolvedParent
      rawTarget="$(readlink "$linkPath" 2>/dev/null || true)"
      [[ -n "$rawTarget" ]] || return 1
      if [[ "$rawTarget" = /* ]]; then
        targetPath="$rawTarget"
      else
        targetPath="$(dirname "$linkPath")/$rawTarget"
      fi
      resolvedParent="$(cd -P "$(dirname "$targetPath")" 2>/dev/null && pwd)" || return 1
      printf '%s/%s\n' "$resolvedParent" "$(basename "$targetPath")"
    }

    isKnownDotfilesTarget() {
      local linkTarget="$1"
      local checkoutRoot
      for checkoutRoot in \
        "''${DOTFILES_CHECKOUT:-}" \
        "$HOME/dotfiles" \
        "$HOME/github/dotfiles"
      do
        if [[ "$checkoutRoot" = /* ]]; then
          case "$linkTarget" in
            "$checkoutRoot"|"$checkoutRoot"/*) return 0 ;;
          esac
        fi
      done
      return 1
    }

    # ~/.ssh needs a preserving migration: unlike the config directories
    # below, it can contain host keys and known_hosts that Home Manager does
    # not own. Copy those files out of the Stow target before linkGeneration
    # writes managed SSH files, leaving the repository target untouched.
    if [[ -L "$HOME/.ssh" ]]; then
      sshLinkTarget="$(resolveLinkTarget "$HOME/.ssh" || true)"
      if [[ -n "$sshLinkTarget" ]] && isKnownDotfilesTarget "$sshLinkTarget"; then
        verboseEcho "Migrating legacy stow symlink $HOME/.ssh -> $sshLinkTarget"
        run rm $VERBOSE_ARG "$HOME/.ssh"
        run mkdir -p $VERBOSE_ARG "$HOME/.ssh"
        # Agent sockets and other special files are ephemeral runtime state and
        # cannot be recreated by an unprivileged activation on macOS.
        run ${pkgs.rsync}/bin/rsync -a --no-specials --no-devices $VERBOSE_ARG \
          --exclude '/agent/' "$sshLinkTarget/" "$HOME/.ssh/"
        run chmod 700 "$HOME/.ssh"
      else
        verboseEcho "Skipping non-stow symlink at $HOME/.ssh -> ''${sshLinkTarget:-<unresolvable>}"
      fi
    fi

    ${lib.concatMapStrings (rel: ''
      if [[ -L "$HOME/${rel}" ]]; then
        linkTarget="$(resolveLinkTarget "$HOME/${rel}" || true)"
        if [[ -n "$linkTarget" ]] && isKnownDotfilesTarget "$linkTarget"; then
          verboseEcho "Removing legacy stow symlink $HOME/${rel} -> $linkTarget"
          run rm $VERBOSE_ARG "$HOME/${rel}"
          run mkdir -p $VERBOSE_ARG "$HOME/${rel}"
        else
          verboseEcho "Skipping non-stow symlink at $HOME/${rel} -> ''${linkTarget:-<unresolvable>} (not inside a known dotfiles checkout)"
        fi
      fi
    '') legacyStowDirs}
  '';
}
