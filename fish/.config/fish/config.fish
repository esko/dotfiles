if status is-interactive
    set -g fish_greeting

    # PATH configuration
    set --local paths \
        $HOME/.cargo/bin \
        $HOME/.local/bin \
        $HOME/bin \
        $HOME/usr/local/bin
    for path in $paths
        if test -d $path
            fish_add_path $path
        end
    end

    alias la='eza --long --all --total-size'
    alias lt='eza --tree'
    alias rm='rm -r'
    alias cp='cp -r'

    bind ctrl-z '__fish_echo fg 2>/dev/null'

    for file in /etc/profile.d/*.sh
        bass source $file 2> /dev/null
    end
        
    # Commands to run in interactive sessions can go here
    bat --completion fish | source
    zoxide init fish --cmd cd | source
    fzf --fish | source
end

# bun
set --export BUN_INSTALL "$HOME/.bun"
set --export PATH $BUN_INSTALL/bin $PATH
