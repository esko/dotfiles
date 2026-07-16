# Fish-to-zsh compatibility layer. Keep functions small and POSIX-friendly so
# the same profile works in container images and macOS.

# Allow pasteable command blocks to contain shell comments in interactive zsh.
setopt interactivecomments

# Do not eval `bun completions` during shell startup. Bun chooses its output
# from $SHELL and can emit Bash's `complete` builtin when the inherited shell is
# stale or unset. Bun-installed completion files are discovered through zsh's
# normal fpath/compinit setup instead.

# Keep the prompt and fzf integrations lazy enough for non-interactive shells.
if [[ -o interactive ]]; then
  # Menu-driven completions (Tab cycles; arrows select) closer to Fish UX.
  if zmodload zsh/complist 2>/dev/null; then
    setopt auto_menu complete_in_word always_to_end
    zstyle ':completion:*' menu select
    zstyle ':completion:*' matcher-list 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' 'r:|[._-]=* r:|=*'
    zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
    zstyle ':completion:*' group-name ''
    if [[ -n ${LS_COLORS:-} ]]; then
      zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
    fi
    bindkey -M menuselect '^[[Z' reverse-menu-complete 2>/dev/null || true
  fi

  # Optional carapace bridge. Cached once — never `source <(carapace …)` at
  # startup (that process substitution has crashed Crostini terminals).
  if [[ ${DOTFILES_CARAPACE:-0} == 1 ]] && (( $+commands[carapace] )); then
    _dotfiles_carapace_init="${XDG_CACHE_HOME:-$HOME/.cache}/carapace/init.zsh"
    if [[ ! -r $_dotfiles_carapace_init ]]; then
      mkdir -p "${_dotfiles_carapace_init:h}"
      if ! carapace _carapace zsh >"$_dotfiles_carapace_init" 2>/dev/null; then
        rm -f "$_dotfiles_carapace_init"
      fi
    fi
    [[ -r $_dotfiles_carapace_init ]] && source "$_dotfiles_carapace_init"
    unset _dotfiles_carapace_init
  fi

  if (( $+commands[fzf] )); then
    source <(fzf --zsh 2>/dev/null) || true
  fi

  # Alt-Up mirrors Fish's directory navigation binding.
  bindkey -s '\e[1;3A' 'cd ..\n'
  bindkey '^F' autosuggest-accept
fi

backup() {
  if (( $# != 1 )); then
    print -u2 "usage: backup FILE|DIRECTORY"
    return 2
  fi
  local target=$1 timestamp backup_path
  if [[ ! -e $target ]]; then
    print -u2 "File or directory '$target' does not exist."
    return 1
  fi
  timestamp=$(date +%Y%m%d_%H%M%S)
  backup_path="${target}_${timestamp}.bak"
  cp -riv -- "$target" "$backup_path"
  print "Created backup: $backup_path"
}

extract() {
  if (( $# != 1 )); then
    print -u2 "usage: extract ARCHIVE"
    return 2
  fi
  local archive=$1
  [[ -f $archive ]] || { print -u2 "Error: '$archive' is not a valid file."; return 1; }
  case $archive in
    *.tar.gz|*.tgz) tar xzf -- "$archive" ;;
    *.tar.bz2|*.tbz2) tar xjf -- "$archive" ;;
    *.tar.xz|*.txz) tar xJf -- "$archive" ;;
    *.tar) tar xf -- "$archive" ;;
    *.zip) unzip -- "$archive" ;;
    *.rar) unrar x -- "$archive" ;;
    *.7z) 7z x -- "$archive" ;;
    *.gz) gunzip -- "$archive" ;;
    *) print -u2 "Error: '$archive' cannot be extracted."; return 1 ;;
  esac
}

mkcd() {
  if (( $# != 1 )); then
    print -u2 "usage: mkcd DIRECTORY"
    return 2
  fi
  mkdir -p -- "$1" && builtin cd -- "$1"
}

rfv() {
  local selection file line
  selection=$(rg --color=always --line-number --no-heading --smart-case "$@" |
    fzf --ansi --preview 'bat --color=always --highlight-line {2} {1}' \
      --preview-window 'up,60%,border-bottom,+{2}+3/3,~3' |
    awk -F: '{print $1 ":" $2}') || return
  [[ -n $selection ]] || return
  file=${selection%%:*}
  line=${selection#*:}
  micro "$file" +"$line"
}

# Pull latest changes when entering a git repository. Disable with
# GIT_AUTO_PULL=0 or for one cd: GIT_AUTO_PULL=0 cd repo
if [[ -o interactive ]]; then
  typeset -g __git_auto_pull_last=""
  typeset -g __git_auto_pull_repo=""
  typeset -g __git_auto_pull_ts=0

  _auto_git_pull_on_cd() {
    [[ "${GIT_AUTO_PULL:-1}" == "0" ]] && return
    (( $+commands[git] )) || return
    git rev-parse --is-inside-work-tree &>/dev/null || return

    local root
    root="$(git rev-parse --show-toplevel 2>/dev/null)" || return

    # Pull once per repo entry; skip when moving within the same repo.
    if [[ "$root" == "$__git_auto_pull_repo" && "$PWD" != "$root" ]]; then
      return
    fi
    __git_auto_pull_repo="$root"

    local now=$(( $(date +%s) ))
    if [[ "$root" == "$__git_auto_pull_last" && $(( now - __git_auto_pull_ts )) -lt 60 ]]; then
      return
    fi
    __git_auto_pull_last="$root"
    __git_auto_pull_ts=$now

    print -u2 "↻ auto-pulling $(basename "$root")..."
    git -C "$root" pull --rebase --autostash --ff-only 2>/dev/null \
      || git -C "$root" pull --rebase --autostash
  }

  chpwd_functions+=(_auto_git_pull_on_cd)
fi

# Keep a useful shell completion for the locally installed agy CLI. Define a
# normal zsh completion function rather than embedding one large quoted command.
if (( $+commands[agy] )); then
  _agy() {
    _arguments \
      '(-c --continue)-c' \
      '(-c --continue)--continue' \
      '--add-dir=[directory]:directory:_directories' \
      '--conversation=[conversation id]' \
      '--dangerously-skip-permissions' \
      '(-i --prompt-interactive)-i' \
      '(-i --prompt-interactive)--prompt-interactive' \
      '--log-file=[path]:file:_files' \
      '--model=[model]' \
      '(-p --print --prompt)-p' \
      '(-p --print --prompt)--print' \
      '(-p --print --prompt)--prompt' \
      '--print-timeout=[seconds]' \
      '--sandbox' \
      '1:subcommand:(changelog help install models plugin plugins update)'
  }
  compdef _agy agy
fi
