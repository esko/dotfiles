if status is-interactive
    # Alt+Up: Go up one directory and repaint prompt
    bind \e\[A 'cd ..; commandline -f repaint'
    
    # Alt+Left/Right: Jump by word (Useful for editing commands)
    bind \e\[1\;3D backward-word
    bind \e\[1\;3C forward-word
end
