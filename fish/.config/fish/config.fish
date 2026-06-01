if status is-interactive
    set -g fish_greeting ""

    # Keybindings (Ctrl+Z to foreground tasks)
    bind \cz '__fish_echo fg 2>/dev/null'
end


# Added by Antigravity CLI installer
set -gx PATH "/home/esko/.local/bin" $PATH

# Enforce included Cursor Agent CLI budget before interactive runs.
function agent --wraps agent
    /home/esko/.cursor/hooks/agent-budget-check.sh $argv
end

# Enable Truecolor for micro
set -gx MICRO_TRUECOLOR 1
