if status is-interactive
    if command -v bat >/dev/null
        bat --completion fish | source
    end
    
    if command -v zoxide >/dev/null
        zoxide init fish --cmd cd | source
    end
    
    if command -v fzf >/dev/null
        fzf --fish | source
    end
end
