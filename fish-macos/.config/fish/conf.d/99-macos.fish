# Initialize Homebrew paths (critical for SSH on Apple Silicon)
if test -d /opt/homebrew
    fish_add_path /opt/homebrew/bin /opt/homebrew/sbin
end

if status is-interactive
    # Mac-specific abbreviations
    abbr -a bi 'brew install'
    abbr -a bs 'brew search'
    abbr -a brewup 'brew update; and brew upgrade'
    abbr -a bserv 'brew services'
end
