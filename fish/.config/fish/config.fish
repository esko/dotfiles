if status is-interactive
    set -g fish_greeting ""

    # Keybindings (Ctrl+Z to foreground tasks)
    bind \cz '__fish_echo fg 2>/dev/null'
end
