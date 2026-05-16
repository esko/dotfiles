# Bun configuration
set --export BUN_INSTALL "$HOME/.bun"

# PATH configuration
set --local custom_paths \
    $BUN_INSTALL/bin \
    $HOME/.cargo/bin \
    $HOME/.local/bin \
    $HOME/bin \
    $HOME/usr/local/bin

for path in $custom_paths
    if test -d $path
        fish_add_path $path
    end
end

# Load System Profiles (Uses the Bass plugin)
if test -d /etc/profile.d
    for file in /etc/profile.d/*.sh
        bass source $file 2> /dev/null
    end
end
