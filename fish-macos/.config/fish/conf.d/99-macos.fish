# Initialize Homebrew for Apple Silicon or Intel macOS.
set -l brew_bin
if test -x /opt/homebrew/bin/brew
    set brew_bin /opt/homebrew/bin/brew
else if test -x /usr/local/bin/brew
    set brew_bin /usr/local/bin/brew
end

if test -n "$brew_bin"
    eval ($brew_bin shellenv)
end

if status is-interactive
    # Mac-specific abbreviations
    abbr -a bi 'brew install'
    abbr -a bs 'brew search'
    abbr -a brewup 'brew update; and brew upgrade'
    abbr -a bserv 'brew services'
end
