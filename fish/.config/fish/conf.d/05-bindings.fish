if status is-interactive
    # Alt+Up: Go up one directory and repaint prompt
    bind alt-up 'cd ..; commandline -f repaint'
end
