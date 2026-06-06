if status is-interactive
    set -g fish_greeting ""

    # Keybindings (Ctrl+Z to foreground tasks)
    bind \cz '__fish_echo fg 2>/dev/null'
end

fish_add_path --global "$HOME/.local/bin" "$HOME/.cargo/bin"

# Enable Truecolor for micro
set -gx MICRO_TRUECOLOR 1
