function rfv -d "Search text, select with FZF, open in Editor"
    set -l selection (rg --color=always --line-number --no-heading --smart-case $argv | \
        fzf --ansi \
            --preview 'bat --color=always --highlight-line {2} {1}' \
            --preview-window 'up,60%,border-bottom,+{2}+3/3,~3' | \
        awk -F: '{print $1 ":" $2}')

    if test -n "$selection"
        set -l file (echo $selection | cut -d: -f1)
        set -l line (echo $selection | cut -d: -f2)
        micro $file +$line
    end
end
